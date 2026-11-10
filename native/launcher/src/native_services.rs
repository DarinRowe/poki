//! Experimental banner-free automation over the same paired CoreDevice services as the desktop
//! bridge. One worker owns a persistent paired tunnel and screen-media session for the active run,
//! matching the desktop bridge's control timing without sharing state with XCTest or PokiLauncher.

use crate::{
    Result, apps, ax,
    device::{Device, Pairing},
    gesture::{Drag, Fingers, Pinch},
    not_sent_error, stream,
};
use base64::Engine;
use idevice::{
    RsdService,
    core_device::hid::{
        ButtonState, IndigoHidClient, KeyboardUsage, MainKeyboardService,
        TOUCHSCREEN_STATE_CONTACT, TOUCHSCREEN_STATE_RELEASE, UniversalHidServiceClient,
    },
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{net::IpAddr, path::PathBuf, time::Duration};

type Touch = UniversalHidServiceClient<Box<dyn idevice::ReadWrite>>;
type Indigo = IndigoHidClient<Box<dyn idevice::ReadWrite>>;

#[derive(Clone, Deserialize)]
pub struct ClientConfig {
    #[serde(default = "default_address")]
    device_address: IpAddr,
    pairing_file: PathBuf,
    #[serde(default)]
    host_name: Option<String>,
}

fn default_address() -> IpAddr {
    IpAddr::from([10, 7, 0, 1])
}
fn tap_duration() -> u64 {
    50
}
fn drag_duration() -> u64 {
    500
}

#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub(crate) enum Request {
    Reset,
    WarmInput,
    AxTree {
        #[serde(default)]
        include_offscreen: bool,
    },
    Screenshot,
    Tap {
        x: u16,
        y: u16,
        #[serde(default = "tap_duration")]
        duration_ms: u64,
    },
    LongPress {
        x: u16,
        y: u16,
        duration_ms: u64,
    },
    Drag {
        x1: u16,
        y1: u16,
        x2: u16,
        y2: u16,
        #[serde(default = "drag_duration")]
        duration_ms: u64,
        #[serde(default)]
        hold_ms: u64,
        #[serde(default)]
        end_hold_ms: u64,
    },
    Pinch {
        x: u16,
        y: u16,
        start_distance: f64,
        end_distance: f64,
        #[serde(default)]
        angle: f64,
        #[serde(default = "drag_duration")]
        duration_ms: u64,
    },
    DrawStrokes {
        strokes: crate::gesture::Strokes,
    },
    DrawFingers {
        fingers: Fingers,
    },
    TypeKeys {
        text: String,
        #[serde(default)]
        clear: bool,
        #[serde(default)]
        frequency: Option<u64>,
    },
    TypeText {
        text: String,
        #[serde(default)]
        clear: bool,
        #[serde(default)]
        submit: bool,
    },
    Key {
        key: String,
        #[serde(default)]
        modifiers: Vec<String>,
        #[serde(default = "one")]
        count: usize,
    },
    Button {
        button: String,
    },
    LaunchApp {
        bundle_id: String,
        #[serde(default)]
        terminate_existing: bool,
    },
    TerminateApp {
        bundle_id: String,
    },
    PasteboardGet,
    PasteboardSet {
        text: String,
    },
}
impl Request {
    pub(crate) fn validate(&self) -> Result<()> {
        validate(self)
    }
}
fn one() -> usize {
    1
}

pub(crate) struct Call {
    pub(crate) request: Request,
    pub(crate) answer: Box<dyn FnOnce(Result<Value>) + Send>,
}

pub(crate) fn parse_request(text: &str) -> std::result::Result<Request, serde_json::Error> {
    serde_json::from_str(text)
}

/// Serves calls in order, as the desktop bridge does. A transport error drops the tunnel so the next
/// request opens a fresh one; an action is never replayed after an uncertain result.
pub(crate) async fn serve(
    config: ClientConfig,
    mut calls: tokio::sync::mpsc::UnboundedReceiver<Call>,
) {
    let mut session: Option<Session> = None;
    while let Some(call) = calls.recv().await {
        if matches!(&call.request, Request::Reset) {
            session = None;
            (call.answer)(Ok(json!({"reset": true})));
            continue;
        }
        let timeout = call.request.timeout();
        let result = tokio::time::timeout(timeout, async {
            if session.is_none() {
                session = Some(Session::connect(&config).await?);
            }
            session.as_mut().unwrap().execute(call.request).await
        })
        .await
        .unwrap_or_else(|_| {
            Err(format!(
                "native service timed out after {} seconds",
                timeout.as_secs()
            )
            .into())
        });
        if result.is_err() {
            session = None;
        }
        (call.answer)(result);
    }
}

impl Request {
    /// Bounds a wedged phone service so the next PokiCore retry gets a fresh tunnel. Input gets its
    /// declared gesture time plus recovery room; no timed-out action is ever replayed.
    fn timeout(&self) -> Duration {
        let gesture_ms = match self {
            Self::Tap { duration_ms, .. }
            | Self::LongPress { duration_ms, .. }
            | Self::Drag { duration_ms, .. }
            | Self::Pinch { duration_ms, .. } => Some(*duration_ms),
            _ => None,
        };
        gesture_ms
            .map(|milliseconds| Duration::from_millis(milliseconds.saturating_add(10_000)))
            .unwrap_or_else(|| match self {
                Self::AxTree { .. } | Self::Screenshot => Duration::from_secs(15),
                Self::WarmInput => Duration::from_secs(25),
                Self::Reset => Duration::from_secs(2),
                _ => Duration::from_secs(30),
            })
    }
}

struct Session {
    device: Device,
    media: Option<InputMedia>,
}

impl Session {
    async fn connect(config: &ClientConfig) -> Result<Self> {
        let mut pairing = Pairing::read(&config.pairing_file, config.host_name.as_deref())
            .map_err(|error| error.detail)?;
        let device = Device::open(config.device_address, &mut pairing, Duration::from_secs(20))
            .await
            .map_err(|error| error.detail)?;
        Ok(Self {
            device,
            media: None,
        })
    }

    async fn execute(&mut self, request: Request) -> Result<Value> {
        request.validate()?;
        match request {
            Request::AxTree { include_offscreen } => {
                ax::read_tree(
                    &mut self.device.adapter,
                    &self.device.rsd,
                    include_offscreen,
                )
                .await
            }
            Request::Screenshot => {
                let mut dvt = idevice::dvt::remote_server::RemoteServerClient::connect_rsd(
                    &mut self.device.adapter,
                    &mut self.device.rsd,
                )
                .await?;
                dvt.read_message(0).await?;
                let mut screenshot =
                    idevice::dvt::screenshot::ScreenshotClient::new(&mut dvt).await?;
                let bytes = screenshot.take_screenshot().await?;
                Ok(json!({"base64": base64::engine::general_purpose::STANDARD.encode(bytes)}))
            }
            Request::LaunchApp {
                bundle_id,
                terminate_existing,
            } => {
                apps::launch(
                    &mut self.device.adapter,
                    &mut self.device.rsd,
                    apps::LaunchRequest {
                        bundle_id: Some(bundle_id),
                        name: None,
                        arguments: vec![],
                        environment: Default::default(),
                        terminate_existing,
                    },
                )
                .await
            }
            Request::TerminateApp { bundle_id } => {
                apps::terminate(&mut self.device.adapter, &mut self.device.rsd, &bundle_id).await
            }
            Request::PasteboardGet => {
                let mut client = idevice::core_device::PasteboardServiceClient::connect_rsd(
                    &mut self.device.adapter,
                    &mut self.device.rsd,
                )
                .await?;
                let snapshot = client.get(idevice::core_device::GENERAL_PASTEBOARD).await?;
                Ok(json!({"text": snapshot.text()}))
            }
            Request::PasteboardSet { text } => {
                let mut client = idevice::core_device::PasteboardServiceClient::connect_rsd(
                    &mut self.device.adapter,
                    &mut self.device.rsd,
                )
                .await?;
                client
                    .set_text(&text, idevice::core_device::GENERAL_PASTEBOARD)
                    .await?;
                Ok(json!({"copied": true}))
            }
            request => input(&mut self.device, &mut self.media, request).await,
        }
    }
}

fn validate(request: &Request) -> Result<()> {
    match request {
        Request::Tap { duration_ms, .. }
        | Request::LongPress { duration_ms, .. }
        | Request::Drag { duration_ms, .. }
        | Request::Pinch { duration_ms, .. }
            if !(1..=60_000).contains(duration_ms) =>
        {
            Err("duration_ms must be 1..60000".into())
        }
        Request::TypeKeys { text, .. } if text.chars().count() > 2_000 => {
            Err("text is at most 2000 characters".into())
        }
        Request::TypeText { text, .. } if text.len() > 1024 * 1024 => {
            Err("text exceeds 1 MiB".into())
        }
        Request::Key { count, .. } if !(1..=200).contains(count) => {
            Err("key count must be 1..200".into())
        }
        Request::LaunchApp { bundle_id, .. } if bundle_id.is_empty() => {
            Err("bundle_id must not be empty".into())
        }
        Request::TerminateApp { bundle_id } if bundle_id.is_empty() => {
            Err("bundle_id must not be empty".into())
        }
        Request::PasteboardSet { text } if text.len() > 1024 * 1024 => {
            Err("text exceeds 1 MiB".into())
        }
        Request::DrawStrokes { strokes } => strokes.validate(),
        Request::DrawFingers { fingers } => fingers.validate(),
        _ => Ok(()),
    }
}

struct InputMedia {
    _client: idevice::core_device::DisplayServiceClient<Box<dyn idevice::ReadWrite>>,
    _receivers: tokio::task::JoinSet<()>,
    touch: Touch,
}

impl InputMedia {
    async fn connect(device: &mut Device) -> Result<Self> {
        let opened = stream::start_screen_media_stream(&mut device.adapter, &mut device.rsd, 1)
            .await
            .map_err(not_sent_error)?;
        let mut receivers = tokio::task::JoinSet::new();
        for socket in [opened.audio_udp, opened.video_udp] {
            receivers.spawn(async move { while socket.recv().await.is_ok() {} });
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
        let touch = Touch::connect_rsd(&mut device.adapter, &mut device.rsd)
            .await
            .map_err(not_sent_error)?;
        Ok(Self {
            _client: opened.client,
            _receivers: receivers,
            touch,
        })
    }
}

async fn input(
    device: &mut Device,
    media: &mut Option<InputMedia>,
    request: Request,
) -> Result<Value> {
    if media.is_none() {
        *media = Some(InputMedia::connect(device).await?);
    }
    if matches!(request, Request::WarmInput) {
        return Ok(json!({"ready": true}));
    }
    let request = match request {
        Request::TypeText {
            text,
            clear,
            submit,
        } => {
            let mut keyboard = Keyboard::connect(device).await?;
            let outcome = crate::pasteboard::paste_text(
                &mut device.adapter,
                &device.rsd,
                &mut keyboard,
                &text,
                clear,
                submit,
                None,
            )
            .await;
            let cleanup = keyboard.close().await;
            let value = outcome?;
            cleanup?;
            return Ok(value);
        }
        request => request,
    };
    // The HID connection stays alive between calls. Unlike the short-lived desktop
    // helper, it needs no disconnect grace period after every action. PokiCore
    // owns UI settling and verification for both automation methods.
    input_open(device, media.as_mut().unwrap(), request).await?;
    Ok(json!({"sent": true, "screen_change_verified": false}))
}

async fn input_open(device: &mut Device, media: &mut InputMedia, request: Request) -> Result<()> {
    match request {
        Request::Tap { x, y, duration_ms } | Request::LongPress { x, y, duration_ms } => {
            held_tap(&mut media.touch, x, y, duration_ms).await?;
        }
        Request::Drag {
            x1,
            y1,
            x2,
            y2,
            duration_ms,
            hold_ms,
            end_hold_ms,
        } => {
            Drag {
                x1,
                y1,
                x2,
                y2,
                duration_ms,
                hold_ms,
                end_hold_ms,
            }
            .send(&mut media.touch)
            .await?;
        }
        Request::Pinch {
            x,
            y,
            start_distance,
            end_distance,
            angle,
            duration_ms,
        } => {
            Pinch {
                x,
                y,
                start_distance,
                end_distance,
                angle,
                duration_ms,
            }
            .send(&mut media.touch)
            .await?;
        }
        Request::DrawStrokes { strokes } => {
            strokes.send(&mut media.touch).await?;
        }
        Request::DrawFingers { fingers } => {
            fingers.send(&mut media.touch).await?;
        }
        Request::TypeKeys {
            text,
            clear,
            frequency,
        } => {
            let mut keyboard = Keyboard::connect(device).await?;
            let outcome = type_keys(&mut keyboard, &text, clear, frequency).await;
            let cleanup = keyboard.close().await;
            outcome?;
            cleanup?;
        }
        Request::Key {
            key,
            modifiers,
            count,
        } => {
            let mut keyboard = Keyboard::connect(device).await?;
            let modifiers = modifiers
                .iter()
                .map(|name| modifier_usage(name))
                .collect::<Result<Vec<_>>>()?;
            let usage = key_usage(&key)?;
            let outcome: Result<()> = async {
                for _ in 0..count {
                    chord(&mut keyboard, usage, &modifiers).await?;
                }
                Ok(())
            }
            .await;
            let cleanup = keyboard.close().await;
            outcome?;
            cleanup?;
        }
        Request::Button { button } => {
            let mut hid = Indigo::connect_rsd(&mut device.adapter, &mut device.rsd)
                .await
                .map_err(not_sent_error)?;
            let (usage, duration) = button_usage(&button)?;
            hid.send_button(0x0c, usage, ButtonState::Down).await?;
            tokio::time::sleep(Duration::from_millis(duration)).await;
            hid.send_button(0x0c, usage, ButtonState::Up).await?;
        }
        _ => unreachable!(),
    }
    Ok(())
}

pub(crate) struct Keyboard {
    pub(crate) hid: Touch,
    pub(crate) service: MainKeyboardService,
}
impl Keyboard {
    async fn connect(device: &mut Device) -> Result<Self> {
        let mut hid = Touch::connect_rsd(&mut device.adapter, &mut device.rsd)
            .await
            .map_err(not_sent_error)?;
        let service = hid.create_main_keyboard().await.map_err(not_sent_error)?;
        tokio::time::sleep(Duration::from_millis(150)).await;
        Ok(Self { hid, service })
    }
    async fn close(&mut self) -> Result<()> {
        self.hid.remove_main_keyboard(&mut self.service).await?;
        Ok(())
    }
}

pub(crate) async fn held_tap(hid: &mut Touch, x: u16, y: u16, duration_ms: u64) -> Result<()> {
    hid.send_touchscreen(TOUCHSCREEN_STATE_CONTACT, x, y, None)
        .await?;
    tokio::time::sleep(Duration::from_millis(duration_ms)).await;
    hid.send_touchscreen(TOUCHSCREEN_STATE_RELEASE, x, y, None)
        .await?;
    Ok(())
}

fn modifier_usage(name: &str) -> Result<u64> {
    Ok(match name.to_ascii_lowercase().as_str() {
        "command" | "cmd" | "meta" => 0xe3,
        "control" | "ctrl" => 0xe0,
        "option" | "alt" => 0xe2,
        "shift" => 0xe1,
        _ => return Err(format!("Unknown modifier: {name}").into()),
    })
}

fn key_usage(name: &str) -> Result<u64> {
    let name = name.to_ascii_lowercase();
    Ok(match name.as_str() {
        "return" | "enter" => 0x28,
        "escape" | "esc" => 0x29,
        "backspace" | "delete" => 0x2a,
        "tab" => 0x2b,
        "space" => 0x2c,
        "forward_delete" => 0x4c,
        "right" | "arrowright" => 0x4f,
        "left" | "arrowleft" => 0x50,
        "down" | "arrowdown" => 0x51,
        "up" | "arrowup" => 0x52,
        "home" => 0x4a,
        "end" => 0x4d,
        "pageup" | "page_up" => 0x4b,
        "pagedown" | "page_down" => 0x4e,
        "0" => 0x27,
        value if value.len() == 1 && value.as_bytes()[0].is_ascii_lowercase() => {
            4 + (value.as_bytes()[0] - b'a') as u64
        }
        value if value.len() == 1 && matches!(value.as_bytes()[0], b'1'..=b'9') => {
            0x1e + (value.as_bytes()[0] - b'1') as u64
        }
        _ => return Err(format!("Unknown keyboard key: {name}").into()),
    })
}

fn char_usage(c: char) -> Result<(u64, bool)> {
    Ok(match c {
        'a'..='z' => (4 + (c as u64 - 'a' as u64), false),
        'A'..='Z' => (4 + (c as u64 - 'A' as u64), true),
        '1'..='9' => (0x1e + (c as u64 - '1' as u64), false),
        '0' => (0x27, false),
        '\n' => (0x28, false),
        '\u{8}' => (0x2a, false),
        '\t' => (0x2b, false),
        ' ' => (0x2c, false),
        '!' => (0x1e, true),
        '@' => (0x1f, true),
        '#' => (0x20, true),
        '$' => (0x21, true),
        '%' => (0x22, true),
        '^' => (0x23, true),
        '&' => (0x24, true),
        '*' => (0x25, true),
        '(' => (0x26, true),
        ')' => (0x27, true),
        '-' => (0x2d, false),
        '_' => (0x2d, true),
        '=' => (0x2e, false),
        '+' => (0x2e, true),
        '[' => (0x2f, false),
        '{' => (0x2f, true),
        ']' => (0x30, false),
        '}' => (0x30, true),
        '\\' => (0x31, false),
        '|' => (0x31, true),
        ';' => (0x33, false),
        ':' => (0x33, true),
        '\'' => (0x34, false),
        '"' => (0x34, true),
        '`' => (0x35, false),
        '~' => (0x35, true),
        ',' => (0x36, false),
        '<' => (0x36, true),
        '.' => (0x37, false),
        '>' => (0x37, true),
        '/' => (0x38, false),
        '?' => (0x38, true),
        _ => return Err(format!("Banner-free typing cannot yet type {c:?}").into()),
    })
}

async fn type_keys(
    keyboard: &mut Keyboard,
    text: &str,
    clear: bool,
    frequency: Option<u64>,
) -> Result<()> {
    if clear {
        chord(keyboard, 0x04, &[0xe3]).await?;
        chord(keyboard, 0x2a, &[]).await?;
    }
    let shift = KeyboardUsage::new(0xe1)?;
    // One down and one up report per character. Half the requested character interval preserves
    // PokiCore's humanized WDA speed; without one, match the desktop bridge's 12 ms report gap.
    let gap = frequency
        .map(|value| Duration::from_micros(500_000 / value.clamp(1, 240)))
        .unwrap_or(Duration::from_millis(12));
    for character in text.chars() {
        let (usage, shifted) = char_usage(character)?;
        let key = KeyboardUsage::new(usage as u16)?;
        if shifted {
            keyboard
                .hid
                .main_keyboard_key_down(&mut keyboard.service, shift)
                .await?;
        }
        keyboard
            .hid
            .main_keyboard_key_down(&mut keyboard.service, key)
            .await?;
        tokio::time::sleep(gap).await;
        keyboard
            .hid
            .main_keyboard_key_up(&mut keyboard.service, key)
            .await?;
        if shifted {
            keyboard
                .hid
                .main_keyboard_key_up(&mut keyboard.service, shift)
                .await?;
        }
        tokio::time::sleep(gap).await;
    }
    keyboard
        .hid
        .set_main_keyboard_usages(&mut keyboard.service, [])
        .await?;
    Ok(())
}

pub(crate) async fn chord(keyboard: &mut Keyboard, key: u64, modifiers: &[u64]) -> Result<()> {
    let modifiers = modifiers
        .iter()
        .map(|value| KeyboardUsage::new(*value as u16))
        .collect::<std::result::Result<Vec<_>, _>>()?;
    let key = KeyboardUsage::new(key as u16)?;
    for modifier in &modifiers {
        keyboard
            .hid
            .main_keyboard_key_down(&mut keyboard.service, *modifier)
            .await?;
    }
    keyboard
        .hid
        .main_keyboard_key_down(&mut keyboard.service, key)
        .await?;
    tokio::time::sleep(Duration::from_millis(50)).await;
    keyboard
        .hid
        .main_keyboard_key_up(&mut keyboard.service, key)
        .await?;
    keyboard
        .hid
        .set_main_keyboard_usages(&mut keyboard.service, [])
        .await?;
    tokio::time::sleep(Duration::from_millis(50)).await;
    Ok(())
}

fn button_usage(name: &str) -> Result<(u64, u64)> {
    Ok(match name.replace('_', "-").as_str() {
        "home" => (0x40, 80),
        "power" | "lock" | "sleep" => (0x30, 200),
        "volume-up" | "volumeUp" => (0xe9, 80),
        "volume-down" | "volumeDown" => (0xea, 80),
        "mute" => (0xe2, 80),
        _ => return Err(format!("Unknown hardware button: {name}").into()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn requests_keep_wda_typing_speed_and_backspace() {
        let request = parse_request(r#"{"op":"type_keys","text":"a\b","frequency":55}"#).unwrap();
        assert!(matches!(
            request,
            Request::TypeKeys {
                frequency: Some(55),
                ..
            }
        ));
        assert_eq!(char_usage('\u{8}').unwrap(), (0x2a, false));
    }

    #[test]
    fn accepts_wda_and_bridge_button_names() {
        assert_eq!(button_usage("volumeUp").unwrap(), (0xe9, 80));
        assert_eq!(button_usage("volume_down").unwrap(), (0xea, 80));
    }

    #[test]
    fn service_deadlines_leave_room_for_gestures_and_bound_reads() {
        let drag = parse_request(r#"{"op":"drag","x1":1,"y1":2,"x2":3,"y2":4,"duration_ms":900}"#)
            .unwrap();
        assert_eq!(drag.timeout(), Duration::from_millis(10_900));
        assert_eq!(
            parse_request(r#"{"op":"ax_tree"}"#).unwrap().timeout(),
            Duration::from_secs(15)
        );
        assert_eq!(
            parse_request(r#"{"op":"reset"}"#).unwrap().timeout(),
            Duration::from_secs(2)
        );
    }
}
