//! Developer Mode (iOS 16 and later), through the amfi lockdown service. Turning it on restarts
//! the phone; after the restart iOS asks the person to confirm and enter the passcode.
use super::Phone;
use crate::{Error, Reporter, Result};
use idevice::{IdeviceService, amfi::AmfiClient};
use std::time::Duration;

pub async fn status(phone: &Phone) -> Result<bool> {
    let provider = phone.provider()?;
    let mut amfi = AmfiClient::connect(&*provider).await?;
    Ok(amfi.get_developer_mode_status().await?)
}

/// Turns Developer Mode on. Returns `Ok(true)` when it was already on, `Ok(false)` when the phone
/// is restarting and the person has to confirm there. The phone must have no passcode-locked
/// screen for the second step; iOS asks for the passcode itself.
pub async fn enable(phone: &Phone, reporter: &Reporter) -> Result<bool> {
    reporter.step("devmode", "Turning on Developer Mode");
    let provider = phone.provider()?;
    let mut amfi = AmfiClient::connect(&*provider).await?;
    if amfi.get_developer_mode_status().await? {
        reporter.done("devmode", Some("Developer Mode is already on.".into()));
        return Ok(true);
    }
    // Shows the switch in Settings > Privacy & Security first, so the person can also do it by hand.
    let _ = amfi.reveal_developer_mode_option_in_ui().await;
    match amfi.enable_developer_mode().await {
        Ok(()) => {}
        Err(idevice::IdeviceError::PasswordProtected) | Err(idevice::IdeviceError::DeviceLocked) => {
            return Err(Error::NeedsPerson("Unlock the iPhone, then try Developer Mode again. iOS only turns it on from an unlocked phone.".into()));
        }
        Err(e) => return Err(e.into()),
    }
    reporter.waiting("devmode", "The iPhone restarts. When it is back, tap Turn On and enter the passcode.");
    Ok(false)
}

/// After the restart: waits until the phone is back and Developer Mode reads on, up to `wait`.
pub async fn wait_until_on(udid: &str, reporter: &Reporter, wait: Duration) -> Result<()> {
    let deadline = tokio::time::Instant::now() + wait;
    loop {
        if tokio::time::Instant::now() > deadline {
            return Err(Error::NeedsPerson("Developer Mode is still off. On the iPhone, open Settings > Privacy & Security > Developer Mode and turn it on.".into()));
        }
        if let Ok(phones) = Phone::list().await {
            if let Some(phone) = phones.into_iter().find(|p| p.udid == udid) {
                if let Ok(provider) = phone.provider() {
                    if let Ok(mut amfi) = AmfiClient::connect(&*provider).await {
                        if let Ok(true) = amfi.get_developer_mode_status().await {
                            // Settings may still show the "Turn on Developer Mode?" sheet; accept it when asked.
                            let _ = amfi.accept_developer_mode().await;
                            reporter.done("devmode", Some("Developer Mode is on.".into()));
                            return Ok(());
                        }
                    }
                }
            }
        }
        tokio::time::sleep(Duration::from_secs(2)).await;
    }
}
