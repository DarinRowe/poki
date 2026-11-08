//! Deploys Poki's relay Worker (`deploy/cf-relay/worker.js`, bundled into this binary) to the
//! person's own Cloudflare account through the API, the same upload DEPLOY.md documents.
//! The API token is used for the deploy and not kept unless the person asks.
use crate::{Error, Result, Reporter};
use serde::{Deserialize, Serialize};

pub const WORKER_JS: &str = include_str!("../../../deploy/cf-relay/worker.js");
pub const SCRIPT_NAME: &str = "poki-relay";
pub const COMPATIBILITY_DATE: &str = "2025-10-01";
const API: &str = "https://api.cloudflare.com/client/v4";

pub const VARS: [(&str, &str); 7] = [
    ("MAX_BODY", "4194304"),
    ("REQ_TIMEOUT_MS", "180000"),
    ("PER_MINUTE", "60"),
    ("CONCURRENT", "4"),
    ("LABEL_DAILY", "5000"),
    ("GLOBAL_DAILY", "8000"),
    ("GLOBAL_DAILY_SECONDS", "80000"),
];

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Deployed {
    pub account_id: String,
    pub account_name: String,
    pub address: String,
    pub first_deploy: bool,
    pub deployed_at: i64,
    /// `poki://setup?relay=<address>`, for the QR the phone scans.
    pub phone_link: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Account {
    pub id: String,
    pub name: String,
}

#[derive(Deserialize)]
struct Envelope<T> {
    success: bool,
    #[serde(default)]
    errors: Vec<ApiError>,
    result: Option<T>,
}
#[derive(Deserialize)]
struct ApiError {
    code: i64,
    message: String,
}

pub struct Cloudflare {
    http: reqwest::Client,
    token: String,
}

impl Cloudflare {
    pub fn new(token: &str) -> Result<Self> {
        if token.trim().len() < 20 {
            return Err(Error::msg("That does not look like a Cloudflare API token."));
        }
        Ok(Cloudflare { http: reqwest::Client::builder().timeout(std::time::Duration::from_secs(120)).build()?, token: token.trim().to_string() })
    }

    async fn parse<T: serde::de::DeserializeOwned>(res: reqwest::Response, what: &str) -> Result<T> {
        let status = res.status();
        let text = res.text().await?;
        let env: Envelope<T> = serde_json::from_str(&text).map_err(|_| Error::msg(format!("Cloudflare answered {what} with HTTP {status}: {}", text.chars().take(200).collect::<String>())))?;
        if !env.success {
            let msg = env.errors.iter().map(|e| format!("{} ({})", e.message, e.code)).collect::<Vec<_>>().join("; ");
            return Err(match env.errors.first().map(|e| e.code) {
                Some(10000) | Some(9109) | Some(10001) => Error::msg("Cloudflare rejected the API token. Make a token with the 'Edit Cloudflare Workers' template at dash.cloudflare.com/profile/api-tokens."),
                _ => Error::msg(format!("Cloudflare: {msg}")),
            });
        }
        env.result.ok_or_else(|| Error::msg(format!("Cloudflare gave no result for {what}")))
    }

    pub async fn accounts(&self) -> Result<Vec<Account>> {
        let res = self.http.get(format!("{API}/accounts?per_page=50")).bearer_auth(&self.token).send().await?;
        let list: Vec<Account> = Self::parse(res, "the account list").await?;
        if list.is_empty() {
            return Err(Error::msg("This token sees no Cloudflare account. Give it 'Account: Workers Scripts: Edit' on your account."));
        }
        Ok(list)
    }

    async fn has_secret(&self, account: &str) -> Result<Option<bool>> {
        let res = self.http.get(format!("{API}/accounts/{account}/workers/scripts/{SCRIPT_NAME}/secrets")).bearer_auth(&self.token).send().await?;
        if res.status().as_u16() == 404 {
            return Ok(None);
        }
        #[derive(Deserialize)]
        struct S {
            name: String,
        }
        let list: Vec<S> = Self::parse(res, "the secret list").await?;
        Ok(Some(list.iter().any(|s| s.name == "TOKEN_SECRET")))
    }

    async fn migration_tag(&self, account: &str) -> Result<Option<String>> {
        let res = self.http.get(format!("{API}/accounts/{account}/workers/services/{SCRIPT_NAME}")).bearer_auth(&self.token).send().await?;
        if res.status().as_u16() == 404 {
            return Ok(None);
        }
        let v: serde_json::Value = Self::parse(res, "the Worker").await?;
        Ok(Some(v["default_environment"]["script"]["migration_tag"].as_str().unwrap_or("").to_string()))
    }

    /// Uploads the Worker. Keeps an existing TOKEN_SECRET, makes one on the first deploy.
    pub async fn deploy(&self, account: &Account, reporter: &Reporter) -> Result<Deployed> {
        reporter.part("relay", 0.1, Some("Checking the account".into()));
        let existing_secret = self.has_secret(&account.id).await?;
        let tag = self.migration_tag(&account.id).await?;
        let first_deploy = existing_secret.is_none();
        let mut bindings = vec![
            serde_json::json!({"type": "durable_object_namespace", "name": "DEVICE", "class_name": "DeviceRelay"}),
            serde_json::json!({"type": "durable_object_namespace", "name": "BUDGET", "class_name": "Budget"}),
        ];
        for (k, v) in VARS {
            bindings.push(serde_json::json!({"type": "plain_text", "name": k, "text": v}));
        }
        let mut metadata = serde_json::json!({
            "main_module": "index.js",
            "compatibility_date": COMPATIBILITY_DATE,
            "bindings": bindings,
            "observability": {"enabled": false},
        });
        if existing_secret == Some(true) {
            metadata["keep_bindings"] = serde_json::json!(["secret_text"]);
        } else {
            use rand::RngCore;
            let mut raw = [0u8; 32];
            rand::thread_rng().fill_bytes(&mut raw);
            metadata["bindings"].as_array_mut().unwrap().push(serde_json::json!({"type": "secret_text", "name": "TOKEN_SECRET", "text": hex::encode(raw)}));
        }
        match tag.as_deref() {
            None | Some("") => metadata["migrations"] = serde_json::json!({"new_tag": "v1", "new_sqlite_classes": ["DeviceRelay", "Budget"]}),
            Some("v1") => {}
            Some(other) => return Err(Error::msg(format!("The Worker {SCRIPT_NAME} in this account has migration tag {other}, which this version does not know. Deploy it with ./deploy.sh instead."))),
        }
        reporter.part("relay", 0.4, Some("Uploading the Worker".into()));
        let form = reqwest::multipart::Form::new()
            .part("metadata", reqwest::multipart::Part::text(metadata.to_string()).mime_str("application/json").unwrap())
            .part("index.js", reqwest::multipart::Part::text(WORKER_JS).file_name("index.js").mime_str("application/javascript+module").unwrap());
        let res = self.http.put(format!("{API}/accounts/{}/workers/scripts/{SCRIPT_NAME}", account.id)).bearer_auth(&self.token).multipart(form).send().await?;
        let _: serde_json::Value = Self::parse(res, "the upload").await?;

        reporter.part("relay", 0.7, Some("Turning on the workers.dev address".into()));
        let res = self.http.post(format!("{API}/accounts/{}/workers/scripts/{SCRIPT_NAME}/subdomain", account.id)).bearer_auth(&self.token).json(&serde_json::json!({"enabled": true, "previews_enabled": false})).send().await?;
        let _: serde_json::Value = Self::parse(res, "the subdomain switch").await?;
        let res = self.http.get(format!("{API}/accounts/{}/workers/subdomain", account.id)).bearer_auth(&self.token).send().await?;
        let sub: serde_json::Value = Self::parse(res, "the subdomain").await?;
        let sub = sub["subdomain"].as_str().ok_or_else(|| Error::msg("This account has no workers.dev subdomain yet. Open Workers & Pages in the dashboard once to pick one, then deploy again."))?;
        let address = format!("https://{SCRIPT_NAME}.{sub}.workers.dev");

        reporter.part("relay", 0.9, Some("Checking the relay answers".into()));
        let mut up = false;
        for _ in 0..10 {
            if crate::mcp::relay_up(&address).await.unwrap_or(false) {
                up = true;
                break;
            }
            tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        }
        if !up {
            return Err(Error::msg(format!("The Worker is uploaded, but {address} does not answer yet. Wait a minute and check it from Relay → Check.")));
        }
        Ok(Deployed { account_id: account.id.clone(), account_name: account.name.clone(), address: address.clone(), first_deploy, deployed_at: crate::keeper::now(), phone_link: phone_link(&address) })
    }
}

pub fn phone_link(address: &str) -> String { format!("poki://setup?relay={}", urlencode(address)) }

fn path() -> Result<std::path::PathBuf> { Ok(crate::paths::state_dir()?.join("relay.json")) }
pub fn remembered() -> Result<Option<Deployed>> { Ok(std::fs::read_to_string(path()?).ok().and_then(|t| serde_json::from_str(&t).ok())) }
pub fn remember(d: &Deployed) -> Result<()> {
    std::fs::write(path()?, serde_json::to_vec_pretty(d)?)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn worker_is_bundled() {
        assert!(super::WORKER_JS.contains("DeviceRelay"));
        assert!(super::WORKER_JS.len() > 10_000);
        assert_eq!(super::phone_link("https://poki-relay.me.workers.dev"), "poki://setup?relay=https%3A%2F%2Fpoki-relay.me.workers.dev");
    }
}

fn urlencode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(b as char),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}
