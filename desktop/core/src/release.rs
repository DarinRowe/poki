//! Poki's releases on GitHub: `ios-v*` tags with `Poki-external-<v>-<b>.ipa`, `Poki-<v>-<b>.ipa`,
//! `Poki-signing.zip` and `SHA256SUMS`. Poki Setup installs the external edition: its loopback
//! comes from the person's proxy app, which a team profile can sign; the built-in tunnel cannot.
use crate::{Error, Result, Reporter, paths};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::PathBuf;

pub const DEFAULT_REPO: &str = "JosssphZhou/poki";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Release {
    pub tag: String,
    pub version: String,
    pub build: String,
    pub published_at: String,
    pub prerelease: bool,
    pub ipa_url: String,
    pub ipa_name: String,
    pub signing_url: Option<String>,
    pub sums_url: Option<String>,
    pub notes: String,
}

#[derive(Deserialize)]
struct GhRelease {
    tag_name: String,
    prerelease: bool,
    draft: bool,
    published_at: Option<String>,
    body: Option<String>,
    assets: Vec<GhAsset>,
}
#[derive(Deserialize)]
struct GhAsset {
    name: String,
    browser_download_url: String,
}

pub fn repo() -> String { std::env::var("POKI_RELEASE_REPO").unwrap_or_else(|_| DEFAULT_REPO.into()) }

fn client() -> Result<reqwest::Client> {
    Ok(reqwest::Client::builder().user_agent(format!("PokiSetup/{}", crate::VERSION)).timeout(std::time::Duration::from_secs(600)).build()?)
}

/// The newest `ios-v*` release that ships the external IPA.
pub async fn latest() -> Result<Release> {
    let list: Vec<GhRelease> = client()?
        .get(format!("https://api.github.com/repos/{}/releases?per_page=20", repo()))
        .header("Accept", "application/vnd.github+json")
        .send()
        .await?
        .error_for_status()
        .map_err(|e| Error::msg(format!("Could not read Poki's releases from GitHub ({e}). Check the connection and try again.")))?
        .json()
        .await?;
    for r in list.into_iter().filter(|r| !r.draft && r.tag_name.starts_with("ios-v")) {
        let Some(ipa) = r.assets.iter().find(|a| a.name.starts_with("Poki-external-") && a.name.ends_with(".ipa")) else { continue };
        let version = r.tag_name.trim_start_matches("ios-v").to_string();
        let build = ipa.name.trim_end_matches(".ipa").rsplit('-').next().unwrap_or("").to_string();
        return Ok(Release {
            tag: r.tag_name.clone(),
            version,
            build,
            published_at: r.published_at.clone().unwrap_or_default(),
            prerelease: r.prerelease,
            ipa_url: ipa.browser_download_url.clone(),
            ipa_name: ipa.name.clone(),
            signing_url: r.assets.iter().find(|a| a.name == "Poki-signing.zip").map(|a| a.browser_download_url.clone()),
            sums_url: r.assets.iter().find(|a| a.name == "SHA256SUMS").map(|a| a.browser_download_url.clone()),
            notes: r.body.unwrap_or_default(),
        });
    }
    Err(Error::msg(format!("No Poki release with an installable IPA was found at github.com/{}.", repo())))
}

/// Downloads the IPA (and the signing zip) into the cache, checks SHA-256 against SHA256SUMS.
pub async fn fetch(release: &Release, reporter: &Reporter) -> Result<(PathBuf, Option<PathBuf>)> {
    let dir = paths::cache_dir()?.join(&release.tag);
    std::fs::create_dir_all(&dir)?;
    let ipa = dir.join(&release.ipa_name);
    let sums = match &release.sums_url {
        Some(u) => Some(client()?.get(u).send().await?.error_for_status()?.text().await?),
        None => None,
    };
    let expected = sums.as_ref().and_then(|s| s.lines().find(|l| l.ends_with(&release.ipa_name)).and_then(|l| l.split_whitespace().next()).map(|h| h.to_lowercase()));
    if !(ipa.is_file() && expected.as_deref().map(|e| sha256_file(&ipa).ok().as_deref() == Some(e)).unwrap_or(false)) {
        download(&release.ipa_url, &ipa, reporter, "release").await?;
        if let Some(e) = &expected {
            let got = sha256_file(&ipa)?;
            if &got != e {
                let _ = std::fs::remove_file(&ipa);
                return Err(Error::msg("The downloaded IPA does not match the release's SHA256SUMS. Try again; if it repeats, the download is being altered on the way."));
            }
        }
    }
    let signing = match &release.signing_url {
        Some(u) => {
            let p = dir.join("Poki-signing.zip");
            if !p.is_file() {
                download(u, &p, reporter, "release").await?;
            }
            Some(p)
        }
        None => None,
    };
    Ok((ipa, signing))
}

pub async fn download(url: &str, to: &std::path::Path, reporter: &Reporter, step: &str) -> Result<()> {
    use futures_util::StreamExt;
    let res = client()?.get(url).send().await?.error_for_status()?;
    let total = res.content_length();
    let tmp = to.with_extension("part");
    let mut file = tokio::fs::File::create(&tmp).await?;
    let mut stream = res.bytes_stream();
    let mut got: u64 = 0;
    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        tokio::io::AsyncWriteExt::write_all(&mut file, &chunk).await?;
        got += chunk.len() as u64;
        if let Some(t) = total {
            reporter.part(step, got as f64 / t as f64, Some(format!("{:.1} of {:.1} MB", got as f64 / 1e6, t as f64 / 1e6)));
        }
    }
    tokio::io::AsyncWriteExt::flush(&mut file).await?;
    drop(file);
    std::fs::rename(&tmp, to)?;
    Ok(())
}

pub fn sha256_file(path: &std::path::Path) -> Result<String> {
    let mut f = std::fs::File::open(path)?;
    let mut h = Sha256::new();
    std::io::copy(&mut f, &mut h)?;
    Ok(hex::encode(h.finalize()))
}
