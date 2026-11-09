//! Poki Setup's core: everything the desktop app and the `poki-setup` command do, with no UI in it.
//!
//! - [`device`]: the iPhone over USB (usbmuxd) or Wi-Fi (the pairing record): pairing, facts,
//!   Developer Mode, installing, the app container, the developer disk image, logs.
//! - [`pairshare`]: hands the pairing file to Poki on the phone over the local network, as the
//!   `poki://pairing?url=…&sha256=…` link Poki opens from a QR code.
//! - [`apple`]: the Apple account (GSA login with SRP and 2FA, anisette) and the developer portal
//!   (teams, devices, certificates, App IDs, app groups, profiles).
//! - [`sign`]: takes Poki's release IPA and signs it for a team: bundle ids, app groups,
//!   entitlements, profiles, every nested bundle, with the pure-Rust apple-codesign.
//! - [`release`]: Poki's release IPAs from GitHub, checked against their digests.
//! - [`keeper`]: the phones this computer set up, their expiry, what is due.
//! - [`mcp`]: connector links, client snippets, and a `tools/list` check.
//! - [`relay`]: deploys `deploy/cf-relay` to the person's own Cloudflare account.
//! - [`support`]: a support bundle with the secrets taken out.
//!
//! Licences: this crate is AGPL-3.0-only like the rest of Poki. The GSA login follows Apple's
//! protocol as implemented in SideStore's icloud-auth (MPL-2.0) and Dadoum's Sideloader
//! (GPL-3.0); the entitlement rule is AltSign's (AGPL-3.0). See THIRD_PARTY_NOTICES.md.

pub mod agent;
pub mod apple;
pub mod device;
pub mod error;
pub mod keeper;
pub mod mcp;
pub mod pairshare;
pub mod paths;
pub mod progress;
pub mod relay;
pub mod release;
pub mod setup;
pub mod sign;
pub mod support;

pub use error::{Error, Result};
pub use progress::{Progress, Reporter};

/// The app's own version, for the About screen and the support bundle.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
/// The build number baked in by the build scripts (the commit count), when there is one.
pub const BUILD: Option<&str> = option_env!("POKI_SETUP_BUILD");

/// `0.2.1-312`: the version and build, as the app shows it and as update checks compare it.
pub fn full_version() -> String {
    match BUILD.filter(|b| !b.is_empty()) {
        Some(b) => format!("{VERSION}-{b}"),
        None => VERSION.to_string(),
    }
}
/// Poki's bundle id as released; a free team gets `<id>.<team>`.
pub const POKI_BUNDLE_ID: &str = "nz.zheha.poki";
/// Poki's app group as released.
pub const POKI_APP_GROUP: &str = "group.nz.zheha.poki";
