//! Lockdown pairing over USB (the Trust This Computer dance) and the records it leaves behind.
//!
//! The record is what Poki on the phone needs to talk to its own developer services through the
//! loopback, so it is saved on this computer (`paths::pairings_dir`), given to usbmuxd, and handed
//! to the phone with [`crate::pairshare`].
use super::{LABEL, Phone};
use crate::{Error, Progress, Reporter, Result, paths};
use idevice::{IdeviceService, lockdown::LockdownClient, pairing_file::PairingFile, usbmuxd::UsbmuxdConnection};
use std::{path::PathBuf, time::Duration};

pub const HOST_NAME: &str = "Poki Setup";

pub fn record_path(udid: &str) -> Result<PathBuf> {
    Ok(paths::pairings_dir()?.join(format!("{udid}.plist")))
}

/// The record saved on this computer for `udid`, if any.
pub fn saved(udid: &str) -> Result<Option<PairingFile>> {
    let path = record_path(udid)?;
    if !path.exists() {
        return Ok(None);
    }
    Ok(Some(PairingFile::read_from_file(&path)?))
}

/// The saved record's bytes, as Poki wants them (a lockdown pairing plist, UDID included).
pub fn saved_bytes(udid: &str) -> Result<Option<Vec<u8>>> {
    let path = record_path(udid)?;
    if !path.exists() {
        return Ok(None);
    }
    Ok(Some(std::fs::read(path)?))
}

/// Whether the saved record still opens a session with the phone.
pub async fn verify(phone: &Phone) -> Result<bool> {
    let Some(record) = saved(&phone.udid)? else { return Ok(false) };
    let provider = phone.provider()?;
    let mut lockdown = LockdownClient::connect(&*provider).await?;
    match lockdown.start_session(&record).await {
        Ok(_) => Ok(true),
        Err(idevice::IdeviceError::InvalidHostID) => Ok(false),
        Err(e) => Err(e.into()),
    }
}

/// Pairs over USB. Waits for the person to tap Trust and enter the passcode (up to `wait`), then
/// tests the record, saves it on this computer and with usbmuxd. Returns the record's bytes.
pub async fn pair(phone: &Phone, reporter: &Reporter, wait: Duration) -> Result<Vec<u8>> {
    if !phone.is_usb() {
        return Err(Error::device("Pairing needs the cable. Plug the iPhone in with a data cable."));
    }
    reporter.step("pair", "Pairing with the iPhone");
    let mut mux = UsbmuxdConnection::default().await?;
    let buid = mux.get_buid().await?;
    let provider = phone.provider()?;
    let mut lockdown = LockdownClient::connect(&*provider).await?;

    // A record this computer or usbmuxd already holds is kept when it still works: the phone then
    // shows no dialog, and Poki keeps the identity it knows.
    if let Some(existing) = saved(&phone.udid)? {
        if lockdown.start_session(&existing).await.is_ok() {
            reporter.note("pair", "This iPhone already trusts this computer.");
            reporter.done("pair", None);
            return Ok(std::fs::read(record_path(&phone.udid)?)?);
        }
        let mut lockdown2 = LockdownClient::connect(&*provider).await?;
        std::mem::swap(&mut lockdown, &mut lockdown2);
    } else if let Ok(Some(existing)) = super::mux_pairing_record(&phone.udid).await {
        if lockdown.start_session(&existing).await.is_ok() {
            let mut existing = existing;
            existing.udid = Some(phone.udid.clone());
            let bytes = existing.serialize()?;
            std::fs::write(record_path(&phone.udid)?, &bytes)?;
            reporter.note("pair", "Using the trust this computer already has with the iPhone.");
            reporter.done("pair", None);
            return Ok(bytes);
        }
        let mut lockdown2 = LockdownClient::connect(&*provider).await?;
        std::mem::swap(&mut lockdown, &mut lockdown2);
    }

    let host_id = uuid::Uuid::new_v4().to_string().to_uppercase();
    reporter.waiting("pair", "On the iPhone: tap Trust, then enter the passcode.");
    let pairing = tokio::time::timeout(wait, lockdown.pair(host_id, buid, Some(HOST_NAME)))
        .await
        .map_err(|_| Error::NeedsPerson("The iPhone did not answer the Trust dialog in time. Unlock it, plug it in again and tap Trust.".into()))??;
    let mut record = pairing;
    record.udid = Some(phone.udid.clone());

    // Test it before anything is saved.
    let mut check = LockdownClient::connect(&*provider).await?;
    check.start_session(&record).await?;

    let bytes = record.clone().serialize()?;
    std::fs::write(record_path(&phone.udid)?, &bytes)?;
    if let Err(e) = mux.save_pair_record(&phone.udid, bytes.clone()).await {
        tracing::warn!("usbmuxd did not keep the pairing record: {e}");
    }
    reporter.done("pair", Some("Paired.".into()));
    reporter.emit(Progress::Note { id: "pair".into(), text: format!("Record saved for {}.", phone.udid) });
    Ok(bytes)
}

/// Forgets the record on this computer and asks the phone to forget this host.
pub async fn unpair(phone: &Phone) -> Result<()> {
    if let Some(record) = saved(&phone.udid)? {
        let provider = phone.provider()?;
        let mut lockdown = LockdownClient::connect(&*provider).await?;
        let _ = lockdown.start_session(&record).await;
        let _ = lockdown.unpair(record.host_id.clone()).await;
    }
    let path = record_path(&phone.udid)?;
    if path.exists() {
        std::fs::remove_file(path)?;
    }
    let _ = LABEL;
    Ok(())
}


/// Lets the iPhone accept this pairing over the network as well as the cable
/// (`com.apple.mobile.wireless_lockdown` / `EnableWifiConnections`). Poki talks to the phone's
/// own services over the loopback, which lockdown treats as a network connection: without this,
/// the record works over USB only and Poki's connections fail with "device socket io failed".
pub async fn enable_network(phone: &Phone) -> Result<()> {
    let record = saved(&phone.udid)?.ok_or_else(|| Error::device("Pair the iPhone first."))?;
    let provider = phone.provider()?;
    let mut lockdown = idevice::lockdown::LockdownClient::connect(&*provider).await?;
    lockdown.start_session(&record).await?;
    lockdown.set_value("EnableWifiConnections", true.into(), Some("com.apple.mobile.wireless_lockdown")).await?;
    Ok(())
}
