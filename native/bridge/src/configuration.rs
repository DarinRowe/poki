use super::Result;
use idevice::{
    core_device::CoreDeviceServiceClient, rsd::RsdHandshake, tcp::handle::AdapterHandle,
};
use serde_json::Value;

pub async fn execute(
    adapter: &mut AdapterHandle,
    rsd: &RsdHandshake,
    method: &str,
    value: Option<Value>,
) -> Result<Value> {
    let action = match method {
        "get_increase_contrast" => "getdeviceincreasecontrast",
        "get_larger_accessibility_sizes" => "getlargeraccessibilitysizesenabled",
        "set_larger_accessibility_sizes" => "setlargeraccessibilitysizesenabled",
        _ => return Err("Unknown configuration method".into()),
    };
    let mut input = plist::Dictionary::new();
    if method == "set_larger_accessibility_sizes" {
        // The service accepts a top-level enabled boolean.
        let enabled = value
            .and_then(|v| v.as_bool())
            .ok_or("value must be a boolean")?;
        input.insert("enabled".into(), enabled.into());
    } else if value.is_some() {
        return Err("Configuration getters do not accept value".into());
    }
    let port = rsd
        .services
        .get("com.apple.coredevice.configuration")
        .ok_or("Device configuration service is unavailable")?
        .port;
    let mut client = CoreDeviceServiceClient::new(adapter.connect(port).await?).await?;
    let response = client
        .invoke_action_with_plist(format!("com.apple.coredevice.action.{action}"), input)
        .await?;
    Ok(serde_json::to_value(response)?)
}
