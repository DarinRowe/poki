//! Poki's releases on GitHub: `ios-v*` (Stable, Beta) and `ios-alpha-*` (Alpha), `ios-prealpha-*` (Pre-alpha) tags with `Poki-external-<v>-<b>.ipa`, `Poki-<v>-<b>.ipa`,
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
    #[serde(default)]
    pub channel: Channel,
    pub ipa_url: String,
    pub ipa_name: String,
    pub signing_url: Option<String>,
    pub sums_url: Option<String>,
    pub notes: String,
}

#[derive(Deserialize, Clone)]
struct GhRelease {
    tag_name: String,
    prerelease: bool,
    draft: bool,
    published_at: Option<String>,
    body: Option<String>,
    #[serde(default)]
    html_url: Option<String>,
    assets: Vec<GhAsset>,
}
#[derive(Deserialize, Clone)]
struct GhAsset {
    name: String,
    browser_download_url: String,
}

pub fn repo() -> String { std::env::var("POKI_RELEASE_REPO").unwrap_or_else(|_| DEFAULT_REPO.into()) }

/// Which releases Poki Setup installs, renews with and offers as its own updates. Each channel
/// includes the ones above it: Beta takes the newest Stable or Beta, Alpha adds alpha builds, Pre-alpha the newest of all.
/// See docs/release-channels.md upstream.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Channel {
    /// `ios-vX.Y.Z` / `desktop-vX.Y.Z` full releases. The default.
    Stable,
    /// The same tags published as prereleases.
    Beta,
    /// `ios-alpha-X.Y.Z-N` / `desktop-alpha-*` early test builds, picked by hand.
    Alpha,
    /// `ios-prealpha-X.Y.Z-N` / `desktop-prealpha-*` snapshots.
    PreAlpha,
}

impl Default for Channel {
    fn default() -> Self { Channel::Stable }
}

impl Channel {
    pub const ALL: [Channel; 4] = [Channel::Stable, Channel::Beta, Channel::Alpha, Channel::PreAlpha];

    pub fn id(self) -> &'static str {
        match self {
            Channel::Stable => "stable",
            Channel::Beta => "beta",
            Channel::Alpha => "alpha",
            Channel::PreAlpha => "pre-alpha",
        }
    }

    pub fn title(self) -> &'static str {
        match self {
            Channel::Stable => "Stable",
            Channel::Beta => "Beta",
            Channel::Alpha => "Alpha",
            Channel::PreAlpha => "Pre-alpha",
        }
    }

    pub fn parse(s: &str) -> Option<Channel> {
        match s.trim().to_ascii_lowercase().replace(['_', ' '], "-").as_str() {
            "stable" => Some(Channel::Stable),
            "beta" => Some(Channel::Beta),
            "alpha" => Some(Channel::Alpha),
            "pre-alpha" | "prealpha" => Some(Channel::PreAlpha),
            _ => None,
        }
    }

    /// This channel, then each less stable one in turn: where to look when this one has nothing yet.
    pub fn fallbacks(self) -> impl Iterator<Item = Channel> { Channel::ALL.into_iter().filter(move |c| *c >= self) }

    /// Whether a release of channel `of` is offered to someone on this channel.
    pub fn includes(self, of: Channel) -> bool { of <= self }

    /// The channel a release belongs to, for a product prefix (`ios` or `desktop`), or None when the
    /// tag is not one of that product's.
    pub fn of_tag(product: &str, tag: &str, prerelease: bool) -> Option<Channel> {
        let rest = tag.strip_prefix(product)?.strip_prefix('-')?;
        if rest.starts_with("prealpha-") {
            Some(Channel::PreAlpha)
        } else if rest.starts_with("alpha-") {
            Some(Channel::Alpha)
        } else if rest.starts_with('v') {
            Some(if prerelease { Channel::Beta } else { Channel::Stable })
        } else {
            None
        }
    }
}

impl std::str::FromStr for Channel {
    type Err = Error;
    fn from_str(s: &str) -> Result<Self> { Channel::parse(s).ok_or_else(|| Error::msg(format!("Unknown channel “{s}”. Use stable, beta, alpha or pre-alpha."))) }
}

#[derive(Serialize, Deserialize, Default)]
struct ChannelFile {
    channel: Channel,
}

fn channel_file() -> Result<PathBuf> { Ok(paths::state_dir()?.join("channel.json")) }

/// The chosen channel: `POKI_RELEASE_CHANNEL` when set, else the saved choice, else Stable.
pub fn channel() -> Channel {
    if let Some(c) = std::env::var("POKI_RELEASE_CHANNEL").ok().and_then(|v| Channel::parse(&v)) {
        return c;
    }
    channel_file()
        .ok()
        .and_then(|p| std::fs::read(p).ok())
        .and_then(|b| serde_json::from_slice::<ChannelFile>(&b).ok())
        .map(|f| f.channel)
        .unwrap_or_default()
}

pub fn set_channel(channel: Channel) -> Result<()> {
    let p = channel_file()?;
    let tmp = p.with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_vec_pretty(&ChannelFile { channel })?)?;
    std::fs::rename(tmp, p)?;
    Ok(())
}

fn client() -> Result<reqwest::Client> {
    Ok(reqwest::Client::builder().user_agent(format!("PokiSetup/{}", crate::VERSION)).timeout(std::time::Duration::from_secs(600)).build()?)
}

async fn list() -> Result<Vec<GhRelease>> {
    let mut list: Vec<GhRelease> = client()?
        .get(format!("https://api.github.com/repos/{}/releases?per_page=100", repo()))
        .header("Accept", "application/vnd.github+json")
        .timeout(std::time::Duration::from_secs(30))
        .send()
        .await?
        .error_for_status()
        .map_err(|e| Error::msg(format!("Could not read Poki's releases from GitHub ({e}). Check the connection and try again.")))?
        .json()
        .await?;
    list.retain(|r| !r.draft);
    // Newest first by publication, whatever order GitHub lists them in.
    list.sort_by(|a, b| b.published_at.cmp(&a.published_at));
    Ok(list)
}

/// An installable Poki release (one with the external IPA) from GitHub's answer.
fn installable(r: &GhRelease) -> Option<(Channel, Release)> {
    let channel = Channel::of_tag("ios", &r.tag_name, r.prerelease)?;
    let ipa = r.assets.iter().find(|a| a.name.starts_with("Poki-external-") && a.name.ends_with(".ipa"))?;
    // Poki-external-<version>-<build>.ipa; the tag names the version too for ios-v* releases.
    let stem = ipa.name.trim_start_matches("Poki-external-").trim_end_matches(".ipa");
    let (version, build) = match stem.rsplit_once('-') {
        Some((v, b)) if !v.is_empty() => (v.to_string(), b.to_string()),
        _ => (r.tag_name.trim_start_matches("ios-v").trim_start_matches("ios-prealpha-").trim_start_matches("ios-alpha-").to_string(), String::new()),
    };
    Some((
        channel,
        Release {
            tag: r.tag_name.clone(),
            version,
            build,
            published_at: r.published_at.clone().unwrap_or_default(),
            prerelease: r.prerelease,
            channel,
            ipa_url: ipa.browser_download_url.clone(),
            ipa_name: ipa.name.clone(),
            signing_url: r.assets.iter().find(|a| a.name == "Poki-signing.zip").map(|a| a.browser_download_url.clone()),
            sums_url: r.assets.iter().find(|a| a.name == "SHA256SUMS").map(|a| a.browser_download_url.clone()),
            notes: r.body.clone().unwrap_or_default(),
        },
    ))
}

fn pick_exact(list: &[GhRelease], channel: Channel) -> Option<Release> {
    list.iter().filter_map(installable).find(|(c, _)| channel.includes(*c)).map(|(_, r)| r)
}

/// The newest release the channel offers; when it has none yet, the next less stable channel's,
/// one step at a time (Stable, then Beta, then Alpha, then Pre-alpha).
fn pick(list: &[GhRelease], channel: Channel) -> Option<Release> {
    channel.fallbacks().find_map(|c| pick_exact(list, c))
}

fn none_in(channel: Channel) -> Error {
    Error::msg(format!("No Poki release with an installable IPA is published on the {} channel at github.com/{}. Pick another channel, or choose an IPA file.", channel.title(), repo()))
}

/// The newest installable release on the chosen channel.
pub async fn latest() -> Result<Release> { latest_in(channel()).await }

/// The newest installable release that a channel offers.
pub async fn latest_in(channel: Channel) -> Result<Release> { pick(&list().await?, channel).ok_or_else(|| none_in(channel)) }

/// One channel's row for the picker: its newest release, if any.
#[derive(Debug, Clone, Serialize)]
pub struct ChannelInfo {
    pub id: Channel,
    pub title: &'static str,
    pub selected: bool,
    pub latest: Option<Release>,
}

/// Every channel with its newest release (one GitHub request), the chosen one marked.
pub async fn channels() -> Result<Vec<ChannelInfo>> {
    let chosen = channel();
    let list = list().await.ok();
    Ok(Channel::ALL
        .iter()
        .map(|&c| ChannelInfo { id: c, title: c.title(), selected: c == chosen, latest: list.as_deref().and_then(|l| pick(l, c)) })
        .collect())
}

/// Poki Setup's own update on the chosen channel. Any release on the channel can carry it (an
/// `ios-*` release with the desktop apps attached, or a `desktop-*` one): the asset for this
/// platform, `PokiSetup-<version>-<build>-macos.dmg` or `PokiSetup-<version>-<build>-windows-x64-setup.exe`.
#[derive(Debug, Clone, Serialize)]
pub struct UpdateInfo {
    pub current: String,
    pub latest: Option<String>,
    /// The release page.
    pub url: Option<String>,
    /// The installer for this computer.
    pub asset_url: Option<String>,
    pub asset_name: Option<String>,
    pub newer: bool,
    pub channel: Channel,
}

/// The installer name suffix for this platform.
fn platform_suffix() -> &'static str {
    if cfg!(target_os = "macos") { "-macos.dmg" } else { "-windows-x64-setup.exe" }
}

/// The version in a Poki Setup installer's name, for this platform.
fn desktop_asset_version(name: &str, suffix: &str) -> Option<String> {
    let v = name.strip_prefix("PokiSetup-")?.strip_suffix(suffix)?;
    (!v.is_empty() && v.chars().next()?.is_ascii_digit()).then(|| v.to_string())
}

fn release_channel(r: &GhRelease) -> Option<Channel> {
    Channel::of_tag("desktop", &r.tag_name, r.prerelease).or_else(|| Channel::of_tag("ios", &r.tag_name, r.prerelease))
}

/// The newest Poki Setup installer a channel offers (stepping down like Poki's own releases).
fn pick_desktop<'a>(list: &'a [GhRelease], channel: Channel, suffix: &str) -> Option<(&'a GhRelease, &'a GhAsset, String)> {
    channel.fallbacks().find_map(|want| {
        list.iter()
            .filter(|r| release_channel(r).map(|c| want.includes(c)).unwrap_or(false))
            .find_map(|r| r.assets.iter().find_map(|a| desktop_asset_version(&a.name, suffix).map(|v| (r, a, v))))
    })
}

pub async fn desktop_update() -> Result<UpdateInfo> {
    let channel = channel();
    let current = crate::full_version();
    let list = list().await?;
    let found = pick_desktop(&list, channel, platform_suffix());
    let newer = found.as_ref().map(|(_, _, v)| version_key(v) > version_key(&current)).unwrap_or(false);
    Ok(match found {
        Some((r, a, v)) => UpdateInfo { current, latest: Some(v), url: r.html_url.clone(), asset_url: Some(a.browser_download_url.clone()), asset_name: Some(a.name.clone()), newer, channel },
        None => UpdateInfo { current, latest: None, url: None, asset_url: None, asset_name: None, newer, channel },
    })
}

/// Downloads the newer Poki Setup and opens it: the disk image on a Mac (drag it over the old
/// one), the installer on Windows. Returns where it was saved.
pub async fn install_desktop_update(reporter: &Reporter) -> Result<PathBuf> {
    let info = desktop_update().await?;
    let (Some(url), Some(name), true) = (info.asset_url, info.asset_name, info.newer) else {
        return Err(Error::msg("Poki Setup is up to date."));
    };
    let dir = paths::cache_dir()?.join("updates");
    std::fs::create_dir_all(&dir)?;
    let to = dir.join(&name);
    if !to.is_file() {
        let part = dir.join(format!("{name}.part"));
        download(&url, &part, reporter, "update").await?;
        std::fs::rename(&part, &to)?;
    }
    open_installer(&to)?;
    Ok(to)
}

fn open_installer(path: &std::path::Path) -> Result<()> {
    #[cfg(target_os = "macos")]
    std::process::Command::new("/usr/bin/open").arg(path).spawn()?;
    #[cfg(windows)]
    std::process::Command::new(path).spawn()?;
    #[cfg(not(any(target_os = "macos", windows)))]
    let _ = path;
    Ok(())
}

/// `0.2.1` < `0.2.1-5` < `0.2.2`: numbers compared in order, a build suffix counts after the version.
fn version_key(s: &str) -> Vec<u64> { s.split(['.', '-']).map(|x| x.parse::<u64>().unwrap_or(0)).collect() }

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

#[cfg(test)]
mod tests {
    use super::*;

    fn gh(tag: &str, pre: bool, at: &str, ipa: Option<&str>) -> GhRelease {
        GhRelease {
            tag_name: tag.into(),
            prerelease: pre,
            draft: false,
            published_at: Some(at.into()),
            body: None,
            html_url: None,
            assets: ipa.map(|n| vec![GhAsset { name: n.into(), browser_download_url: format!("https://x/{n}") }]).unwrap_or_default(),
        }
    }

    #[test]
    fn tags_map_to_channels() {
        assert_eq!(Channel::of_tag("ios", "ios-v0.2.7", false), Some(Channel::Stable));
        assert_eq!(Channel::of_tag("ios", "ios-v0.2.7", true), Some(Channel::Beta));
        assert_eq!(Channel::of_tag("ios", "ios-prealpha-0.2.7-252", true), Some(Channel::PreAlpha));
        assert_eq!(Channel::of_tag("ios", "ios-alpha-0.2.8-110", true), Some(Channel::Alpha));
        assert_eq!(Channel::of_tag("desktop", "desktop-alpha-0.2.1-3", true), Some(Channel::Alpha));
        assert!(Channel::PreAlpha.includes(Channel::Alpha) && Channel::Alpha.includes(Channel::Beta) && !Channel::Beta.includes(Channel::Alpha));
        assert_eq!(Channel::parse("alpha"), Some(Channel::Alpha));
        assert_eq!(Channel::of_tag("ios", "v0.1.1", false), None);
        assert_eq!(Channel::of_tag("ios", "desktop-v0.2.0", false), None);
        assert_eq!(Channel::of_tag("desktop", "desktop-prealpha-0.2.1-9", true), Some(Channel::PreAlpha));
        assert_eq!(Channel::parse("Pre-alpha"), Some(Channel::PreAlpha));
        assert_eq!(serde_json::to_string(&Channel::PreAlpha).unwrap(), "\"pre-alpha\"");
    }

    #[test]
    fn channels_include_the_ones_above() {
        let mut list = vec![
            gh("ios-prealpha-0.2.8-260", true, "2026-11-08T05:00:00Z", Some("Poki-external-0.2.8-260.ipa")),
            gh("ios-v0.2.7", true, "2026-11-07T05:00:00Z", Some("Poki-external-0.2.7-12.ipa")),
            gh("ios-v0.2.6", false, "2026-11-06T05:00:00Z", Some("Poki-external-0.2.6-9.ipa")),
            gh("v0.1.1", false, "2026-11-08T06:00:00Z", None),
        ];
        list.sort_by(|a, b| b.published_at.cmp(&a.published_at));
        let p = pick(&list, Channel::PreAlpha).unwrap();
        assert_eq!((p.version.as_str(), p.build.as_str(), p.channel), ("0.2.8", "260", Channel::PreAlpha));
        assert_eq!(pick(&list, Channel::Beta).unwrap().tag, "ios-v0.2.7");
        assert_eq!(pick(&list, Channel::Stable).unwrap().tag, "ios-v0.2.6");
        // Sorted: v0.1.1, prealpha, v0.2.7 (beta), v0.2.6. Without a Stable release, Stable steps
        // down to Beta; with only a Pre-alpha one it takes that; with no ios-* release, nothing.
        assert_eq!(pick(&list[..3], Channel::Stable).unwrap().tag, "ios-v0.2.7");
        assert_eq!(pick(&list[..2], Channel::Stable).unwrap().tag, "ios-prealpha-0.2.8-260");
        assert!(pick(&list[..1], Channel::Stable).is_none());
        assert_eq!(Channel::default(), Channel::Stable);
    }

    #[test]
    fn choice_is_saved() {
        let (_g, _d) = paths::test_home();
        unsafe { std::env::remove_var("POKI_RELEASE_CHANNEL") };
        assert_eq!(channel(), Channel::Stable);
        set_channel(Channel::PreAlpha).unwrap();
        assert_eq!(channel(), Channel::PreAlpha);
    }

    #[test]
    fn desktop_installer_found_on_any_release() {
        let mut ios = gh("ios-prealpha-0.2.8-441", true, "2026-11-08T08:00:00Z", Some("Poki-external-0.2.8-441.ipa"));
        ios.assets.push(GhAsset { name: "PokiSetup-0.2.1-300-macos.dmg".into(), browser_download_url: "https://x/dmg".into() });
        ios.assets.push(GhAsset { name: "PokiSetup-0.2.1-300-windows-x64-setup.exe".into(), browser_download_url: "https://x/exe".into() });
        let list = vec![ios];
        let (_, a, v) = pick_desktop(&list, Channel::Stable, "-macos.dmg").unwrap();
        assert_eq!((a.name.as_str(), v.as_str()), ("PokiSetup-0.2.1-300-macos.dmg", "0.2.1-300"));
        assert_eq!(pick_desktop(&list, Channel::Beta, "-windows-x64-setup.exe").unwrap().2, "0.2.1-300");
        assert!(version_key("0.2.1-300") > version_key("0.2.1-296"));
        assert!(version_key("0.2.1-300") > version_key("0.2.0"));
    }

    #[test]
    fn build_suffix_sorts_after_version() {
        assert!(version_key("0.2.1-5") > version_key("0.2.1"));
        assert!(version_key("0.2.2") > version_key("0.2.1-5"));
    }
}
