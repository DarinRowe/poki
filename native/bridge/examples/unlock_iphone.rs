use idevice::{
    IdeviceService, RsdService,
    core_device::hid::{
        ButtonState, IndigoHidClient, TOUCHSCREEN_STATE_CONTACT, TOUCHSCREEN_STATE_RELEASE,
        UniversalHidServiceClient,
    },
    core_device_proxy::CoreDeviceProxy,
    rsd::RsdHandshake,
    usbmuxd::{UsbmuxdAddr, UsbmuxdConnection},
};
use serde::Deserialize;
use std::{io::Read, time::Duration};

#[path = "../src/stream.rs"]
mod stream;

type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Keypad {
    width: f64,
    height: f64,
    // Indexed by the digit, starting with zero; coordinates are logical screen points.
    digits: [[f64; 2]; 10],
}

impl Keypad {
    fn validate(&self) -> Result<()> {
        if !self.width.is_finite()
            || !self.height.is_finite()
            || self.width < 2.0
            || self.height < 2.0
            || self.digits.iter().enumerate().any(|(i, point)| {
                let [x, y] = *point;
                !x.is_finite()
                    || !y.is_finite()
                    || x < 0.0
                    || y < 0.0
                    || x >= self.width
                    || y >= self.height
                    || self.digits[..i].contains(point)
            })
        {
            return Err("Keypad must contain ten distinct points inside the screen".into());
        }
        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 5 || args[1] != "--udid" || args[3] != "--keypad" || args[2].is_empty() {
        return Err("usage: unlock_iphone --udid ID --keypad LAYOUT.json < passcode".into());
    }
    let keypad: Keypad = serde_json::from_slice(&std::fs::read(&args[4])?)?;
    keypad.validate()?;
    let mut pin = String::new();
    std::io::stdin().take(64).read_to_string(&mut pin)?;
    let pin = pin.trim();
    if pin.len() != 6 || !pin.bytes().all(|c| c.is_ascii_digit()) {
        return Err("Expected six ASCII digits; nothing sent".into());
    }
    tokio::time::timeout(Duration::from_secs(25), unlock(&args[2], pin, &keypad)).await??;
    Ok(())
}

async fn unlock(udid: &str, pin: &str, keypad: &Keypad) -> Result<()> {
    let mut mux = UsbmuxdConnection::default().await?;
    let device = mux.get_device(udid).await?;
    let provider = device.to_provider(UsbmuxdAddr::from_env_var()?, "poki-unlock-skill");
    let proxy = CoreDeviceProxy::connect(&provider).await?;
    let port = proxy.tunnel_info().server_rsd_port;
    let mut adapter = proxy.create_software_tunnel()?.to_async_handle();
    let mut rsd = RsdHandshake::new(adapter.connect(port).await?).await?;
    let mut media = stream::start_screen_media_stream(&mut adapter, &mut rsd, 1).await?;
    let outcome: Result<u128> = async {
        tokio::time::sleep(Duration::from_millis(1000)).await;
        let mut buttons = IndigoHidClient::connect_rsd(&mut adapter, &mut rsd).await?;
        buttons.send_button(0x0c, 0x40, ButtonState::Down).await?;
        tokio::time::sleep(Duration::from_millis(80)).await;
        buttons.send_button(0x0c, 0x40, ButtonState::Up).await?;
        tokio::time::sleep(Duration::from_millis(2000)).await;
        let mut touch = UniversalHidServiceClient::connect_rsd(&mut adapter, &mut rsd).await?;
        tokio::time::sleep(Duration::from_millis(1000)).await;
        let start = std::time::Instant::now();
        for digit in pin.bytes() {
            let [x, y] = keypad.digits[(digit - b'0') as usize];
            let x = (x / (keypad.width - 1.0) * 65535.0).round() as u16;
            let y = (y / (keypad.height - 1.0) * 65535.0).round() as u16;
            touch
                .send_touchscreen(TOUCHSCREEN_STATE_CONTACT, x, y, None)
                .await?;
            tokio::time::sleep(Duration::from_millis(150)).await;
            touch
                .send_touchscreen(TOUCHSCREEN_STATE_RELEASE, x, y, None)
                .await?;
            tokio::time::sleep(Duration::from_millis(450)).await;
        }
        tokio::time::sleep(Duration::from_millis(1000)).await;
        // Keep both input connections alive through the final wait.
        drop(touch);
        drop(buttons);
        Ok(start.elapsed().as_millis())
    }
    .await;
    let stopped = media.client.stop_media_stream().await;
    let elapsed = outcome?;
    stopped?;
    println!(
        "{}",
        serde_json::json!({"input_sent": true, "unlock_verified": false,
        "tap_phase_ms": elapsed, "instruction": "Inspect a fresh screenshot before reporting success. Do not automatically retry."})
    );
    Ok(())
}
