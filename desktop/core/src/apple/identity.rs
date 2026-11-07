//! The signing identity: an RSA-2048 key this computer makes and keeps, and the development
//! certificate Apple issues for it. The private key never leaves this computer.
use super::portal::{Certificate, Portal};
use crate::{Error, Result, paths};
use rsa::pkcs8::{DecodePrivateKey, EncodePrivateKey, EncodePublicKey};
use rsa::RsaPrivateKey;
use serde::{Deserialize, Serialize};

/// A key and the matching certificate, both DER.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Identity {
    pub team_id: String,
    pub certificate: Certificate,
    #[serde(skip)]
    pub key_pkcs8: Vec<u8>,
}

fn key_path(team: &str) -> Result<std::path::PathBuf> { Ok(paths::keys_dir()?.join(format!("{team}.p8"))) }

/// The key for a team: read from disk, or made and saved.
pub fn key_for(team: &str) -> Result<(Vec<u8>, bool)> {
    let path = key_path(team)?;
    if let Ok(pem) = std::fs::read_to_string(&path) {
        if let Ok(k) = RsaPrivateKey::from_pkcs8_pem(&pem) {
            return Ok((k.to_pkcs8_der().map_err(|e| Error::msg(e.to_string()))?.as_bytes().to_vec(), false));
        }
    }
    let mut rng = rand::thread_rng();
    let key = RsaPrivateKey::new(&mut rng, 2048).map_err(|e| Error::msg(format!("could not make a key: {e}")))?;
    let pem = key.to_pkcs8_pem(rsa::pkcs8::LineEnding::LF).map_err(|e| Error::msg(e.to_string()))?;
    write_private(&path, pem.as_bytes())?;
    Ok((key.to_pkcs8_der().map_err(|e| Error::msg(e.to_string()))?.as_bytes().to_vec(), true))
}

/// A throwaway identity with a self-signed "Apple Development" certificate, for checking the
/// signing pipeline without an Apple Account (`poki-setup selftest-sign`). iOS won't trust it.
pub fn self_signed(team: &str) -> Result<Identity> {
    let mut rng = rand::thread_rng();
    let key = RsaPrivateKey::new(&mut rng, 2048).map_err(|e| Error::msg(format!("could not make a key: {e}")))?;
    let der = key.to_pkcs8_der().map_err(|e| Error::msg(e.to_string()))?.as_bytes().to_vec();
    let kp = rcgen_key(&der)?;
    let mut params = rcgen::CertificateParams::new(Vec::<String>::new()).map_err(|e| Error::msg(e.to_string()))?;
    let mut dn = rcgen::DistinguishedName::new();
    dn.push(rcgen::DnType::CommonName, format!("Apple Development: Poki Setup Self-Test ({team})"));
    dn.push(rcgen::DnType::OrganizationalUnitName, team);
    dn.push(rcgen::DnType::OrganizationName, "Poki Setup Self-Test");
    dn.push(rcgen::DnType::CountryName, "US");
    params.distinguished_name = dn;
    params.extended_key_usages = vec![rcgen::ExtendedKeyUsagePurpose::CodeSigning];
    // As Apple's development certificates: codesign rejects a leaf without digitalSignature.
    params.key_usages = vec![rcgen::KeyUsagePurpose::DigitalSignature];
    params.is_ca = rcgen::IsCa::ExplicitNoCa;
    let cert = params.self_signed(&kp).map_err(|e| Error::msg(e.to_string()))?;
    Ok(Identity {
        team_id: team.to_string(),
        certificate: crate::apple::portal::Certificate { certificate_id: "selftest".into(), serial_number: "01".into(), name: "Poki Setup Self-Test".into(), machine_name: "selftest".into(), der: cert.der().to_vec() },
        key_pkcs8: der,
    })
}

fn write_private(path: &std::path::Path, bytes: &[u8]) -> Result<()> {
    std::fs::write(path, bytes)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    }
    Ok(())
}

/// The SubjectPublicKeyInfo of a key, to match Apple's certificate to it.
pub fn spki_of_key(pkcs8: &[u8]) -> Result<Vec<u8>> {
    let key = RsaPrivateKey::from_pkcs8_der(pkcs8).map_err(|e| Error::msg(e.to_string()))?;
    Ok(key.to_public_key().to_public_key_der().map_err(|e| Error::msg(e.to_string()))?.as_bytes().to_vec())
}

pub fn spki_of_cert(der: &[u8]) -> Option<Vec<u8>> {
    use der::{Decode, Encode};
    let cert = x509_cert::Certificate::from_der(der).ok()?;
    cert.tbs_certificate.subject_public_key_info.to_der().ok()
}

pub fn certificate_matches(key_pkcs8: &[u8], cert_der: &[u8]) -> bool {
    match (spki_of_key(key_pkcs8), spki_of_cert(cert_der)) {
        (Ok(a), Some(b)) => a == b,
        _ => false,
    }
}

/// Days until the certificate expires, negative if it has.
pub fn days_left(cert_der: &[u8]) -> Option<i64> {
    use der::Decode;
    let cert = x509_cert::Certificate::from_der(cert_der).ok()?;
    let not_after = cert.tbs_certificate.validity.not_after.to_unix_duration().as_secs() as i64;
    Some((not_after - time::OffsetDateTime::now_utc().unix_timestamp()) / 86_400)
}

pub fn csr_pem(key_pkcs8: &[u8], common_name: &str) -> Result<String> {
    let key_pair = rcgen_key(key_pkcs8)?;
    let mut params = rcgen::CertificateParams::new(Vec::<String>::new()).map_err(|e| Error::msg(e.to_string()))?;
    let mut dn = rcgen::DistinguishedName::new();
    dn.push(rcgen::DnType::CommonName, common_name);
    dn.push(rcgen::DnType::CountryName, "US");
    params.distinguished_name = dn;
    let csr = params.serialize_request(&key_pair).map_err(|e| Error::msg(format!("CSR: {e}")))?;
    csr.pem().map_err(|e| Error::msg(e.to_string()))
}

/// A certificate on the team that matches this computer's key, or a new one. Revokes a stale
/// Poki Setup certificate first when Apple's limit is in the way (free teams allow one).
pub async fn ensure(portal: &mut Portal<'_>, team: &str, reporter: &crate::Reporter) -> Result<Identity> {
    let (key, fresh) = key_for(team)?;
    let certs = portal.certificates(team).await?;
    if !fresh {
        if let Some(c) = certs.iter().find(|c| certificate_matches(&key, &c.der) && days_left(&c.der).unwrap_or(-1) > 1) {
            return Ok(Identity { team_id: team.into(), certificate: c.clone(), key_pkcs8: key });
        }
    }
    reporter.note("identity", "Asking Apple for a signing certificate for this computer");
    let machine_id = machine_id()?;
    let machine_name = format!("Poki Setup on {}", hostname());
    let csr = csr_pem(&key, "Poki Setup")?;
    let submit = portal.submit_csr(team, &csr, &machine_id, &machine_name).await;
    if let Err(Error::Apple { code, .. }) = &submit {
        if *code == 3250 || *code == 7250 || *code == 9100 {
            // Free teams get one development certificate: retire the old Poki Setup one.
            if let Some(old) = certs.iter().find(|c| c.machine_name.starts_with("Poki Setup") || c.name.contains("Poki")) {
                reporter.note("identity", "Replacing this team's previous Poki Setup certificate");
                portal.revoke_certificate(team, &old.serial_number).await?;
                portal.submit_csr(team, &csr, &machine_id, &machine_name).await?;
            } else {
                return Err(Error::apple(*code, "This team already has its one development certificate, made by another computer or app. Revoke it at developer.apple.com (Certificates) or in that app, then try again."));
            }
        } else {
            submit?;
        }
    } else {
        submit?;
    }
    for _ in 0..10 {
        let certs = portal.certificates(team).await?;
        if let Some(c) = certs.into_iter().find(|c| certificate_matches(&key, &c.der)) {
            return Ok(Identity { team_id: team.into(), certificate: c, key_pkcs8: key });
        }
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    }
    Err(Error::msg("Apple accepted the certificate request but has not issued it yet. Try again in a minute."))
}

fn rcgen_key(key_pkcs8: &[u8]) -> Result<rcgen::KeyPair> {
    let pem = RsaPrivateKey::from_pkcs8_der(key_pkcs8).map_err(|e| Error::msg(e.to_string()))?.to_pkcs8_pem(rsa::pkcs8::LineEnding::LF).map_err(|e| Error::msg(e.to_string()))?;
    rcgen::KeyPair::from_pem_and_sign_algo(&pem, &rcgen::PKCS_RSA_SHA256).map_err(|e| Error::msg(format!("CSR key: {e}")))
}

fn machine_id() -> Result<String> {
    let path = paths::state_dir()?.join("machine-id");
    if let Ok(s) = std::fs::read_to_string(&path) {
        if s.trim().len() == 36 {
            return Ok(s.trim().to_string());
        }
    }
    let id = uuid::Uuid::new_v4().to_string().to_uppercase();
    std::fs::write(&path, &id)?;
    Ok(id)
}

pub fn hostname() -> String {
    std::env::var("COMPUTERNAME").ok().or_else(|| std::env::var("HOSTNAME").ok()).or_else(|| std::fs::read_to_string("/etc/hostname").ok().map(|s| s.trim().to_string())).filter(|s| !s.is_empty()).unwrap_or_else(|| "this computer".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn key_csr_and_match() {
        let (_lock, _dir) = crate::paths::test_home();
        let (key, fresh) = key_for("TESTTEAM").unwrap();
        assert!(fresh);
        let (again, fresh2) = key_for("TESTTEAM").unwrap();
        assert!(!fresh2);
        assert_eq!(key, again);
        let pem = csr_pem(&key, "Poki Setup").unwrap();
        assert!(pem.contains("BEGIN CERTIFICATE REQUEST"));
        // A self-signed cert from the same key matches; another key's does not.
        let kp = rcgen_key(&key).unwrap();
        let cert = rcgen::CertificateParams::new(Vec::<String>::new()).unwrap().self_signed(&kp).unwrap();
        assert!(certificate_matches(&key, cert.der()));
        assert!(days_left(cert.der()).unwrap() > 300);
        let (other, _) = key_for("OTHER").unwrap();
        assert!(!certificate_matches(&other, cert.der()));
    }
}
