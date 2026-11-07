//! The iPhone, over USB through usbmuxd or over Wi-Fi with a pairing record.
//!
//! A [`Phone`] is a UDID plus how to reach it; [`Phone::provider`] gives idevice's connection
//! factory for every service. Nothing here drives the phone's screen: pairing, Developer Mode,
//! installing and files are all lockdown services the person confirms on the phone themselves.
pub mod container;
pub mod ddi;
pub mod devmode;
pub mod info;
pub mod install;
pub mod logs;
pub mod pairing;

use crate::{Error, Result};
use idevice::{
    pairing_file::PairingFile,
    provider::{IdeviceProvider, TcpProvider, UsbmuxdProvider},
    usbmuxd::{Connection, UsbmuxdAddr, UsbmuxdConnection},
};
use serde::{Deserialize, Serialize};
use std::net::IpAddr;

pub const LABEL: &str = "poki-setup";

/// How the phone is reached right now.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Link {
    /// Through usbmuxd over the cable.
    Usb,
    /// Through usbmuxd, which found it on the network (macOS and Windows list Wi-Fi-synced phones).
    Muxed { address: IpAddr },
    /// Straight to lockdown on TCP 62078 with our pairing record (any platform, same Wi-Fi).
    Wifi { address: IpAddr },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Phone {
    pub udid: String,
    pub link: Link,
    /// usbmuxd's own id for the attachment, when it came from usbmuxd.
    #[serde(default)]
    pub mux_id: Option<u32>,
}

impl Phone {
    /// The phones usbmuxd knows: USB first, then network ones.
    pub async fn list() -> Result<Vec<Phone>> {
        let mut mux = UsbmuxdConnection::default().await?;
        let devices = mux.get_devices().await?;
        let mut phones: Vec<Phone> = devices
            .into_iter()
            .map(|d| Phone {
                link: match d.connection_type {
                    Connection::Usb => Link::Usb,
                    Connection::Network(ip) => Link::Muxed { address: ip },
                    Connection::Unknown(_) => Link::Usb,
                },
                udid: d.udid,
                mux_id: Some(d.device_id),
            })
            .collect();
        phones.sort_by_key(|p| !matches!(p.link, Link::Usb));
        Ok(phones)
    }

    /// A phone on the same Wi-Fi, reached with the pairing record this computer saved for it.
    pub fn over_wifi(udid: impl Into<String>, address: IpAddr) -> Phone {
        Phone { udid: udid.into(), link: Link::Wifi { address }, mux_id: None }
    }

    /// idevice's connection factory for this phone. Over USB it is usbmuxd's; over Wi-Fi it needs
    /// the pairing record from [`pairing::saved`].
    pub fn provider(&self) -> Result<Box<dyn IdeviceProvider>> {
        match &self.link {
            Link::Usb | Link::Muxed { .. } => Ok(Box::new(UsbmuxdProvider {
                addr: UsbmuxdAddr::from_env_var().unwrap_or_default(),
                tag: 1,
                udid: self.udid.clone(),
                device_id: self.mux_id.unwrap_or(0),
                label: LABEL.into(),
            })),
            Link::Wifi { address } => {
                let pairing_file = pairing::saved(&self.udid)?
                    .ok_or_else(|| Error::device("No pairing record for this iPhone on this computer. Plug it in once to pair."))?;
                Ok(Box::new(TcpProvider { addr: *address, scope_id: None, pairing_file, label: LABEL.into() }))
            }
        }
    }

    pub fn is_usb(&self) -> bool { matches!(self.link, Link::Usb) }
}

/// The pairing record usbmuxd holds for a UDID (macOS and Windows keep one per trusted phone).
pub async fn mux_pairing_record(udid: &str) -> Result<Option<PairingFile>> {
    let mut mux = UsbmuxdConnection::default().await?;
    match mux.get_pair_record(udid).await {
        Ok(p) => Ok(Some(p)),
        Err(idevice::IdeviceError::NotFound) => Ok(None),
        Err(e) => Err(e.into()),
    }
}
