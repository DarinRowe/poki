//! GrandSlam Authentication: Apple ID sign-in with SRP, two-factor, and the Xcode app token.
//!
//! Protocol as in SideStore's icloud-auth (MPL-2.0) and Dadoum's Sideloader (GPL-3.0), written
//! again here in Rust against the plist shapes those projects document.
use super::anisette::{Headers as Anisette, Provider};
use super::srp;
use crate::{Error, Result};
use aes_gcm::aead::{Aead, Payload};
use aes_gcm::KeyInit;
use base64::Engine;
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;

const GS_SERVICE: &str = "https://gsa.apple.com/grandslam/GsService2";
const TRUSTED_DEVICE: &str = "https://gsa.apple.com/auth/verify/trusteddevice";
const VALIDATE: &str = "https://gsa.apple.com/grandslam/GsService2/validate";
const AUTH_INFO: &str = "https://gsa.apple.com/auth";
const SMS_START: &str = "https://gsa.apple.com/auth/verify/phone/";
const SMS_CODE: &str = "https://gsa.apple.com/auth/verify/phone/securitycode";
const GSA_AGENT: &str = "akd/1.0 CFNetwork/978.0.7 Darwin/18.7.0";

/// What a sign-in leaves behind. `gs_idms_token` + `adsid` identify the session to Apple;
/// `sk`/`c` let us ask for app tokens again without the password.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub apple_id: String,
    pub adsid: String,
    pub gs_idms_token: String,
    pub first_name: String,
    pub last_name: String,
    #[serde(with = "b64")]
    pub sk: Vec<u8>,
    #[serde(with = "b64")]
    pub c: Vec<u8>,
}

mod b64 {
    use base64::Engine;
    use serde::{Deserialize, Deserializer, Serializer};
    pub fn serialize<S: Serializer>(v: &Vec<u8>, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&base64::engine::general_purpose::STANDARD.encode(v))
    }
    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<u8>, D::Error> {
        let s = String::deserialize(d)?;
        base64::engine::general_purpose::STANDARD.decode(s).map_err(serde::de::Error::custom)
    }
}

/// A token for one app (we only ever ask for Xcode's).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppToken {
    pub app: String,
    pub token: String,
    /// Unix seconds.
    pub expires_at: i64,
}

impl AppToken {
    pub fn valid_for(&self, secs: i64) -> bool { self.expires_at - time::OffsetDateTime::now_utc().unix_timestamp() > secs }
}

/// How the sign-in ended.
#[derive(Debug)]
pub enum Outcome {
    SignedIn(Session),
    /// Apple wants a second factor. Keep the [`Pending`] and call `trusted_device_code` or `sms_code`.
    NeedsCode(Pending),
}

/// A sign-in waiting for the 2FA code.
#[derive(Debug, Clone)]
pub struct Pending {
    pub apple_id: String,
    password: String,
    session: Session,
    pub via: Factor,
    /// The trusted phone number Apple texted (its id in Apple's list), for an SMS sign-in.
    phone_id: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Factor {
    TrustedDevice,
    Sms,
}

pub struct Client {
    http: reqwest::Client,
    anisette: Provider,
}

type HmacSha256 = Hmac<Sha256>;

fn dict<'a>(v: &'a plist::Value, key: &str) -> Option<&'a plist::Value> { v.as_dictionary()?.get(key) }
fn s<'a>(v: &'a plist::Value, key: &str) -> Option<&'a str> { dict(v, key)?.as_string() }
fn data<'a>(v: &'a plist::Value, key: &str) -> Option<&'a [u8]> { dict(v, key)?.as_data() }

struct Status {
    ec: i64,
    em: String,
    hsc: i64,
    au: Option<String>,
}

fn status(response: &plist::Value) -> Status {
    let st = dict(response, "Status");
    let int = |k: &str| st.and_then(|s| dict(s, k)).and_then(|v| v.as_signed_integer()).unwrap_or(0);
    Status {
        ec: int("ec"),
        em: st.and_then(|s0| s(s0, "em")).unwrap_or("").to_string(),
        hsc: int("hsc"),
        au: st.and_then(|s0| s(s0, "au")).map(|a| a.to_string()),
    }
}

fn apple_error(st: &Status) -> Error {
    tracing::warn!("Apple sign-in status ec={} hsc={} em={:?}", st.ec, st.hsc, st.em);
    let text = match st.ec {
        -20101 | -22406 | -20970 => "Apple ID or password is wrong.".to_string(),
        -20209 | -20751 => "This Apple ID is locked. Unlock it at iforgot.apple.com and try again.".to_string(),
        -22421 => "Apple refused the sign-in from this computer's identity (anisette). Try again in a minute, or choose another anisette server in Settings.".to_string(),
        -20283 => "Apple asked for a passcode or trusted device that this computer cannot provide. Enable two-factor authentication on this Apple ID and try again.".to_string(),
        _ if st.em.is_empty() => format!("Apple's sign-in failed with code {}.", st.ec),
        _ => st.em.clone(),
    };
    Error::apple(st.ec, text)
}

impl Client {
    pub fn new(anisette: Provider) -> Result<Client> { Ok(Client { http: super::http_client()?, anisette }) }

    pub fn anisette(&mut self) -> &mut Provider { &mut self.anisette }

    async fn gs_request(&self, headers: &Anisette, request: plist::Dictionary) -> Result<plist::Value> {
        let mut header = plist::Dictionary::new();
        header.insert("Version".into(), "1.0.1".into());
        let mut root = plist::Dictionary::new();
        root.insert("Header".into(), plist::Value::Dictionary(header));
        root.insert("Request".into(), plist::Value::Dictionary(request));
        let mut body = Vec::new();
        plist::to_writer_xml(&mut body, &plist::Value::Dictionary(root))?;
        tracing::trace!("GSA request: {}", String::from_utf8_lossy(&body));
        let res = self
            .http
            .post(GS_SERVICE)
            .header("Content-Type", "text/x-xml-plist")
            .header("Accept", "*/*")
            .header("User-Agent", headers.get("User-Agent").unwrap_or(GSA_AGENT))
            .header("X-MMe-Client-Info", headers.get("X-Mme-Client-Info").unwrap_or(""))
            .body(body)
            .send()
            .await?
            .error_for_status()?
            .bytes()
            .await?;
        let v: plist::Value = plist::from_bytes(&res)?;
        dict(&v, "Response").cloned().ok_or_else(|| Error::msg("Apple's sign-in service gave an answer without a Response"))
    }

    /// Signs in. Returns `NeedsCode` when Apple wants a second factor.
    pub async fn sign_in(&mut self, apple_id: &str, password: &str) -> Result<Outcome> {
        loop {
            match self.sign_in_once(apple_id, password).await {
                Err(Error::Apple { code: -80045, .. }) | Err(Error::Apple { code: -80046, .. }) if self.anisette.rotate() => continue,
                other => return other,
            }
        }
    }

    async fn sign_in_once(&mut self, apple_id: &str, password: &str) -> Result<Outcome> {
        let anisette = self.anisette.headers().await?;
        let mut client = srp::Client::new();

        let mut init = plist::Dictionary::new();
        init.insert("A2k".into(), plist::Value::Data(client.a_pub.clone()));
        init.insert("cpd".into(), plist::Value::Dictionary(anisette.cpd()));
        init.insert("o".into(), "init".into());
        init.insert("ps".into(), plist::Value::Array(vec!["s2k".into(), "s2k_fo".into()]));
        init.insert("u".into(), apple_id.into());
        let r1 = self.gs_request(&anisette, init).await?;
        let st = status(&r1);
        if st.ec != 0 {
            return Err(apple_error(&st));
        }
        let sp = s(&r1, "sp").unwrap_or("s2k");
        let salt = data(&r1, "s").ok_or_else(|| Error::msg("sign-in: no salt"))?.to_vec();
        let iterations = dict(&r1, "i").and_then(|v| v.as_signed_integer()).ok_or_else(|| Error::msg("sign-in: no iteration count"))? as u32;
        let b_pub = data(&r1, "B").ok_or_else(|| Error::msg("sign-in: no B"))?.to_vec();
        let cookie = data(&r1, "c").map(|c| c.to_vec()).or_else(|| s(&r1, "c").map(|c| c.as_bytes().to_vec())).unwrap_or_default();
        let c_value = dict(&r1, "c").cloned().unwrap_or(plist::Value::String(String::new()));

        let derived = srp::Client::derive_password(password, &salt, iterations, sp == "s2k_fo");
        let m1 = client.process(apple_id, &derived, &salt, &b_pub).map_err(Error::msg)?;
        let _ = cookie;

        let mut complete = plist::Dictionary::new();
        complete.insert("c".into(), c_value);
        complete.insert("M1".into(), plist::Value::Data(m1));
        complete.insert("cpd".into(), plist::Value::Dictionary(anisette.cpd()));
        complete.insert("o".into(), "complete".into());
        complete.insert("u".into(), apple_id.into());
        let r2 = self.gs_request(&anisette, complete).await?;
        let st = status(&r2);
        if st.ec != 0 {
            return Err(apple_error(&st));
        }
        let m2 = data(&r2, "M2").ok_or_else(|| Error::msg("sign-in: no M2"))?;
        if !client.verify_server(m2) {
            return Err(Error::msg("Apple's sign-in answer did not verify (M2 mismatch). Check the clock on this computer and try again."));
        }
        let spd = data(&r2, "spd").ok_or_else(|| Error::msg("sign-in: no spd"))?;
        let spd = decrypt_spd(client.key(), spd)?;
        let session = Session {
            apple_id: apple_id.to_string(),
            adsid: s(&spd, "adsid").unwrap_or("").to_string(),
            gs_idms_token: s(&spd, "GsIdmsToken").unwrap_or("").to_string(),
            first_name: s(&spd, "fn").unwrap_or("").to_string(),
            last_name: s(&spd, "ln").unwrap_or("").to_string(),
            sk: data(&spd, "sk").unwrap_or(&[]).to_vec(),
            c: data(&spd, "c").unwrap_or(&[]).to_vec(),
        };
        if session.adsid.is_empty() || session.gs_idms_token.is_empty() {
            return Err(Error::msg("Apple's sign-in answer had no account token."));
        }
        match (st.hsc, st.au.as_deref()) {
            (409, Some("trustedDeviceSecondaryAuth")) | (_, Some("trustedDeviceSecondaryAuth")) => {
                self.start_trusted_device(&session).await?;
                Ok(Outcome::NeedsCode(Pending { apple_id: apple_id.into(), password: password.into(), session, via: Factor::TrustedDevice, phone_id: 0 }))
            }
            (_, Some("secondaryAuth")) => {
                let phone_id = self.start_sms(&session).await?;
                Ok(Outcome::NeedsCode(Pending { apple_id: apple_id.into(), password: password.into(), session, via: Factor::Sms, phone_id }))
            }
            (_, Some(other)) => Err(Error::msg(format!("Apple asked for a verification step this app does not support ({other})."))),
            _ => Ok(Outcome::SignedIn(session)),
        }
    }

    fn twofa_request(&self, rb: reqwest::RequestBuilder, session: &Session, anisette: &Anisette) -> reqwest::RequestBuilder {
        self.twofa_request_as(rb, session, anisette, "text/x-xml-plist")
    }

    /// The 2FA headers with one Content-Type and Accept (`kind`). The SMS endpoints speak JSON; a
    /// request that carries both the plist and the JSON type is turned away (HTTP 405).
    fn twofa_request_as(&self, rb: reqwest::RequestBuilder, session: &Session, anisette: &Anisette, kind: &str) -> reqwest::RequestBuilder {
        let identity = base64::engine::general_purpose::STANDARD.encode(format!("{}:{}", session.adsid, session.gs_idms_token));
        let mut rb = rb
            .header("X-Apple-Identity-Token", identity)
            .header("X-Apple-App-Info", super::XCODE_APP_ID)
            .header("X-Xcode-Version", super::XCODE_VERSION)
            .header("Content-Type", kind)
            .header("Accept", kind)
            .header("Accept-Language", "en-us")
            .header("User-Agent", "Xcode");
        for (k, v) in &anisette.map {
            if k.eq_ignore_ascii_case("User-Agent") {
                continue;
            }
            rb = rb.header(k.as_str(), v.as_str());
        }
        rb
    }

    async fn start_trusted_device(&mut self, session: &Session) -> Result<()> {
        let anisette = self.anisette.headers().await?;
        let res = self.twofa_request(self.http.get(TRUSTED_DEVICE), session, &anisette).send().await?;
        if !res.status().is_success() {
            return Err(Error::msg(format!("Apple could not send a code to your devices (HTTP {}). Try again, or sign in on a device with the same Apple ID first.", res.status())));
        }
        Ok(())
    }

    /// Asks Apple to text a code. First reads the account's trusted phone numbers (GET /auth, which
    /// also opens the verification on Apple's side), then asks for the text to the first one.
    /// Returns the phone number's id, which the code is checked against.
    async fn start_sms(&mut self, session: &Session) -> Result<u64> {
        let anisette = self.anisette.headers().await?;
        let mut phone_id = 1u64;
        if let Ok(res) = self.twofa_request_as(self.http.get(AUTH_INFO), session, &anisette, "application/json").send().await {
            if let Ok(v) = res.json::<serde_json::Value>().await {
                if let Some(id) = first_phone_id(&v) {
                    phone_id = id;
                }
            }
        }
        let body = serde_json::json!({ "phoneNumber": { "id": phone_id }, "mode": "sms" });
        let mut last = None;
        // PUT is what Apple's own clients send; POST is tried when PUT is turned away.
        for method in [reqwest::Method::PUT, reqwest::Method::POST] {
            let res = self
                .twofa_request_as(self.http.request(method.clone(), SMS_START), session, &anisette, "application/json")
                .body(body.to_string())
                .send()
                .await?;
            if res.status().is_success() {
                return Ok(phone_id);
            }
            tracing::warn!("SMS request {method} answered {}", res.status());
            last = Some(res.status());
            if res.status() != reqwest::StatusCode::METHOD_NOT_ALLOWED {
                break;
            }
        }
        Err(Error::msg(format!(
            "Apple could not text a code to your phone number (HTTP {}). Use a code from one of your Apple devices instead: on an iPhone, iPad or Mac signed in to this Apple Account, open Settings > [your name] > Sign-In & Security > Two-Factor Authentication > Get Verification Code.",
            last.map(|s| s.to_string()).unwrap_or_default()
        )))
    }

    /// Finishes a 2FA sign-in with the code the person typed.
    pub async fn finish(&mut self, pending: Pending, code: &str) -> Result<Session> {
        let code = code.trim();
        if code.len() != 6 || !code.chars().all(|c| c.is_ascii_digit()) {
            return Err(Error::NeedsPerson("The code is six digits.".into()));
        }
        let anisette = self.anisette.headers().await?;
        match pending.via {
            Factor::TrustedDevice => {
                let res = self.twofa_request(self.http.get(VALIDATE), &pending.session, &anisette).header("security-code", code).send().await?;
                let bytes = res.bytes().await?;
                let v: plist::Value = plist::from_bytes(&bytes).unwrap_or(plist::Value::Dictionary(Default::default()));
                let ec = dict(&v, "ec").and_then(|e| e.as_signed_integer()).unwrap_or(0);
                if ec != 0 {
                    let em = s(&v, "em").unwrap_or("");
                    return Err(match ec {
                        -21669 => Error::NeedsPerson("That code was not right. Try again.".into()),
                        _ => Error::apple(ec, if em.is_empty() { format!("Apple rejected the code ({ec}).") } else { em.to_string() }),
                    });
                }
            }
            Factor::Sms => {
                let body = serde_json::json!({ "phoneNumber": { "id": pending.phone_id }, "securityCode": { "code": code }, "mode": "sms" });
                let res = self
                    .twofa_request_as(self.http.post(SMS_CODE), &pending.session, &anisette, "application/json")
                    .body(body.to_string())
                    .send()
                    .await?;
                if !res.status().is_success() {
                    return Err(Error::NeedsPerson("That code was not right. Try again.".into()));
                }
            }
        }
        // Sign in again: this computer is trusted now and Apple hands out the full session.
        match self.sign_in(&pending.apple_id, &pending.password).await? {
            Outcome::SignedIn(s) => Ok(s),
            Outcome::NeedsCode(_) => Err(Error::msg("Apple asked for a code again after the code was accepted. Try once more.")),
        }
    }

    /// The app token for Xcode's services, which the developer portal wants.
    pub async fn xcode_token(&mut self, session: &Session) -> Result<AppToken> {
        self.app_token(session, super::XCODE_APP_ID).await
    }

    pub async fn app_token(&mut self, session: &Session, app: &str) -> Result<AppToken> {
        let anisette = self.anisette.headers().await?;
        let mut mac = <HmacSha256 as Mac>::new_from_slice(&session.sk).map_err(|_| Error::msg("session key is empty; sign in again"))?;
        mac.update(b"apptokens");
        mac.update(session.adsid.as_bytes());
        mac.update(app.as_bytes());
        let checksum = mac.finalize().into_bytes().to_vec();
        let mut req = plist::Dictionary::new();
        req.insert("app".into(), plist::Value::Array(vec![app.into()]));
        req.insert("c".into(), plist::Value::Data(session.c.clone()));
        req.insert("checksum".into(), plist::Value::Data(checksum));
        req.insert("cpd".into(), plist::Value::Dictionary(anisette.cpd()));
        req.insert("o".into(), "apptokens".into());
        req.insert("t".into(), session.gs_idms_token.clone().into());
        req.insert("u".into(), session.adsid.clone().into());
        let r = self.gs_request(&anisette, req).await?;
        let st = status(&r);
        if st.ec != 0 {
            return Err(match st.ec {
                -20101 | -22406 | -21212 => Error::NeedsPerson("Your Apple session has expired. Sign in again.".into()),
                _ => apple_error(&st),
            });
        }
        let et = data(&r, "et").ok_or_else(|| Error::msg("Apple gave no app token"))?;
        let tokens = decrypt_gcm(&session.sk, et)?;
        let entry = dict(&tokens, "t").and_then(|t| dict(t, app)).ok_or_else(|| Error::msg("Apple's app token answer had no Xcode token"))?;
        let token = s(entry, "token").ok_or_else(|| Error::msg("app token without a token"))?.to_string();
        let expiry = dict(entry, "expiry").and_then(|e| e.as_signed_integer()).unwrap_or(0);
        // Apple sends milliseconds since 1970.
        let expires_at = if expiry > 10_000_000_000 { expiry / 1000 } else { expiry };
        Ok(AppToken { app: app.to_string(), token, expires_at })
    }
}

fn decrypt_spd(key: &[u8], spd: &[u8]) -> Result<plist::Value> {
    use aes::cipher::{BlockDecryptMut, KeyIvInit};
    let mut mac = <HmacSha256 as Mac>::new_from_slice(key).unwrap();
    mac.update(b"extra data key:");
    let k = mac.finalize().into_bytes();
    let mut mac = <HmacSha256 as Mac>::new_from_slice(key).unwrap();
    mac.update(b"extra data iv:");
    let iv = mac.finalize().into_bytes();
    let dec = cbc::Decryptor::<aes::Aes256>::new_from_slices(&k, &iv[..16]).map_err(|_| Error::msg("spd key"))?;
    let plain = dec.decrypt_padded_vec_mut::<aes::cipher::block_padding::Pkcs7>(spd).map_err(|_| Error::msg("Apple's session data did not decrypt. Check the password and try again."))?;
    Ok(plist::from_bytes(&plain)?)
}

fn decrypt_gcm(sk: &[u8], et: &[u8]) -> Result<plist::Value> {
    // "XYZ" | 16-byte IV | ciphertext | 16-byte tag, AES-256-GCM with the header as AAD.
    use aes_gcm::aead::generic_array::{GenericArray, typenum::U16};
    if et.len() < 3 + 16 + 16 || &et[..3] != b"XYZ" {
        return Err(Error::msg("Apple's app token has an unknown shape"));
    }
    let cipher = aes_gcm::AesGcm::<aes::Aes256, U16>::new_from_slice(sk).map_err(|_| Error::msg("session key length"))?;
    let plain = cipher
        .decrypt(GenericArray::from_slice(&et[3..19]), Payload { msg: &et[19..], aad: b"XYZ" })
        .map_err(|_| Error::msg("Apple's app token did not decrypt. Sign in again."))?;
    Ok(plist::from_bytes(&plain)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spd_round_trip() {
        use aes::cipher::{BlockEncryptMut, KeyIvInit};
        let key = [7u8; 32];
        let mut d = plist::Dictionary::new();
        d.insert("adsid".into(), "000-1".into());
        let mut plain = Vec::new();
        plist::to_writer_xml(&mut plain, &plist::Value::Dictionary(d)).unwrap();
        let mut mac = <HmacSha256 as Mac>::new_from_slice(&key).unwrap();
        mac.update(b"extra data key:");
        let k = mac.finalize().into_bytes();
        let mut mac = <HmacSha256 as Mac>::new_from_slice(&key).unwrap();
        mac.update(b"extra data iv:");
        let iv = mac.finalize().into_bytes();
        let enc = cbc::Encryptor::<aes::Aes256>::new_from_slices(&k, &iv[..16]).unwrap();
        let ct = enc.encrypt_padded_vec_mut::<aes::cipher::block_padding::Pkcs7>(&plain);
        let v = decrypt_spd(&key, &ct).unwrap();
        assert_eq!(s(&v, "adsid"), Some("000-1"));
    }

    #[test]
    fn gcm_round_trip_16_byte_iv() {
        use aes_gcm::aead::generic_array::typenum::U16;
        let sk = [3u8; 32];
        let mut t = plist::Dictionary::new();
        let mut app = plist::Dictionary::new();
        app.insert("token".into(), "tok".into());
        app.insert("expiry".into(), plist::Value::Integer(1_800_000_000_000i64.into()));
        t.insert(super::super::XCODE_APP_ID.into(), plist::Value::Dictionary(app));
        let mut root = plist::Dictionary::new();
        root.insert("t".into(), plist::Value::Dictionary(t));
        let mut plain = Vec::new();
        plist::to_writer_xml(&mut plain, &plist::Value::Dictionary(root)).unwrap();
        let c = aes_gcm::AesGcm::<aes::Aes256, U16>::new_from_slice(&sk).unwrap();
        let iv = [9u8; 16];
        let ct = c.encrypt(aes_gcm::aead::generic_array::GenericArray::from_slice(&iv), Payload { msg: &plain, aad: b"XYZ" }).unwrap();
        let mut et = b"XYZ".to_vec();
        et.extend_from_slice(&iv);
        et.extend_from_slice(&ct);
        let v = decrypt_gcm(&sk, &et).unwrap();
        assert_eq!(s(dict(dict(&v, "t").unwrap(), super::super::XCODE_APP_ID).unwrap(), "token"), Some("tok"));
    }
}

/// The id of the trusted phone number to text: the one Apple marks for SMS, else the first.
fn first_phone_id(v: &serde_json::Value) -> Option<u64> {
    let phones = v.get("trustedPhoneNumbers").and_then(|p| p.as_array())?;
    let pick = phones.iter().find(|p| p.get("pushMode").and_then(|m| m.as_str()) == Some("sms")).or_else(|| phones.first())?;
    pick.get("id").and_then(|i| i.as_u64())
}

#[cfg(test)]
mod sms_tests {
    #[test]
    fn picks_the_sms_phone() {
        let v = serde_json::json!({ "trustedPhoneNumbers": [ { "id": 3, "pushMode": "voice" }, { "id": 7, "pushMode": "sms" } ] });
        assert_eq!(super::first_phone_id(&v), Some(7));
        assert_eq!(super::first_phone_id(&serde_json::json!({ "trustedPhoneNumbers": [ { "id": 2 } ] })), Some(2));
        assert_eq!(super::first_phone_id(&serde_json::json!({})), None);
    }
}
