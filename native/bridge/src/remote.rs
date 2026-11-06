#[cfg(not(test))]
use super::connect_device;
use super::{InputMedia, NotSent, Request, Result, close_input, execute, execute_connected};
use idevice::{
    remote_pairing::{
        RemotePairingClient, RpPairingFile, RpPairingSocket, connect_tls_psk_tunnel_native,
    },
    rsd::RsdHandshake,
    tcp::handle::AdapterHandle,
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{io::Write, time::Duration};
use tokio::{
    io::{AsyncBufReadExt, BufReader},
    net::TcpStream,
};

#[derive(Deserialize)]
struct Config {
    id: String,
    host: String,
    port: u16,
    pairing_file: String,
}

type Control = RemotePairingClient<RpPairingSocket<TcpStream>>;

enum Transport {
    Local(String),
    Remote(Config),
}

struct Connection {
    adapter: AdapterHandle,
    rsd: RsdHandshake,
    provider: Option<idevice::provider::UsbmuxdProvider>,
    media: Option<InputMedia>,
}

struct Session {
    transport: Transport,
    control: Option<Control>,
    connection: Option<Connection>,
}

impl Session {
    async fn connect(&mut self) -> Result<()> {
        let config = match &self.transport {
            Transport::Local(udid) => {
                // Without a phone, tests hand out tunnels they can unplug.
                #[cfg(test)]
                let connection = tests::connect_local(udid).await?;
                #[cfg(not(test))]
                let connection = {
                    let (adapter, rsd, provider) = connect_device(udid).await?;
                    Connection {
                        adapter,
                        rsd,
                        provider: Some(provider),
                        media: None,
                    }
                };
                self.connection = Some(connection);
                return Ok(());
            }
            Transport::Remote(config) => config,
        };
        if self.control.is_none() {
            let socket = TcpStream::connect((config.host.as_str(), config.port)).await
                .map_err(|_| "Remote pairing is unreachable. Keep Tailscale connected; reconnect the iPhone to Wi-Fi to establish a new session.")?;
            socket.set_nodelay(true)?;
            let mut control = RemotePairingClient::new(RpPairingSocket::new(socket), "poki-mcp");
            let mut record = RpPairingFile::read_from_file(&config.pairing_file).await?;
            control.attempt_pair_verify().await?;
            // Never fall back to pairing or request consent during an ordinary operation.
            control.validate_pairing(&mut record).await?;
            self.control = Some(control);
        }
        let control = self.control.as_mut().unwrap();
        let port = match control.create_tcp_listener().await {
            Ok(port) => port,
            Err(error) => {
                self.control = None;
                return Err(format!("The remote pairing control connection closed: {error}. Reconnect the iPhone to Wi-Fi, then reconnect the device.").into());
            }
        };
        let socket = TcpStream::connect((config.host.as_str(), port)).await
            .map_err(|_| "The iPhone refused a new tunnel. Reconnect it to Wi-Fi, then reconnect the device.")?;
        socket.set_nodelay(true)?;
        let tunnel = connect_tls_psk_tunnel_native(socket, control.encryption_key()).await?;
        let info = tunnel.info.clone();
        let mut adapter = idevice::tcp::adapter::Adapter::new(
            Box::new(tunnel.into_inner()),
            info.client_address.parse()?,
            info.server_address.parse()?,
        )
        .to_async_handle();
        let rsd = RsdHandshake::new(adapter.connect(info.server_rsd_port).await?).await?;
        if rsd
            .properties
            .get("UniqueDeviceID")
            .and_then(plist::Value::as_string)
            != Some(config.id.as_str())
        {
            return Err("Remote device identity does not match the configured iPhone".into());
        }
        self.connection = Some(Connection {
            adapter,
            rsd,
            provider: None,
            media: None,
        });
        Ok(())
    }

    async fn release_input(&mut self) -> Result<()> {
        if let Some(connection) = &mut self.connection {
            close_input(&mut connection.media).await?;
        }
        Ok(())
    }

    async fn request(&mut self, request: Value) -> Result<Value> {
        if request["op"] == "release_input" {
            self.release_input().await?;
            return Ok(json!({"released":true}));
        }
        let action = if request["op"] == "connect" || request["op"] == "reconnect" {
            None
        } else {
            let action: Request = serde_json::from_value(request.clone())?;
            action.validate()?;
            if matches!(
                action,
                Request::InstallApp { .. } | Request::UninstallApp { .. }
            ) {
                return match &self.transport {
                    Transport::Local(udid) => execute(udid, action).await,
                    Transport::Remote(_) => {
                        Err("App installation over remote pairing is not supported".into())
                    }
                };
            }
            Some(action)
        };
        let Some(action) = action else {
            // Keep the working tunnel until its replacement has actually connected.
            // A failed reconnect must not destroy the only usable cellular session.
            if self.connection.is_none() || request["op"] == "reconnect" {
                self.open().await?;
            }
            return Ok(
                json!({"connected":true,"transport":match &self.transport { Transport::Local(_) => "local", Transport::Remote(_) => "remote_pairing" },"device":match &self.transport { Transport::Local(id) => id, Transport::Remote(config) => &config.id }}),
            );
        };
        let local_read = matches!(self.transport, Transport::Local(_)) && action.read_only();
        // A tunnel can die while the helper idles: a pulled cable or a restarted phone leaves its adapter closed.
        // Until an input is written nothing can repeat, so the request rebuilds a closed tunnel once and tries again.
        let mut fresh = false;
        loop {
            if self.connection.is_none() {
                if let Err(error) = self.open().await {
                    return unsent_reply(&action, error);
                }
                fresh = true;
            }
            let Connection {
                adapter,
                rsd,
                provider,
                media,
            } = self.connection.as_mut().unwrap();
            let result = tokio::time::timeout(
                Duration::from_secs(90),
                execute_connected(
                    adapter,
                    rsd,
                    provider
                        .as_ref()
                        .map(|p| p as &dyn idevice::provider::IdeviceProvider),
                    action.clone(),
                    media,
                ),
            )
            .await;
            let error = match result {
                Ok(Ok(value)) => return Ok(value),
                Ok(Err(error)) => error,
                Err(_) => "Remote operation timed out".into(),
            };
            let _ = close_input(media).await;
            // A service or file error does not imply the shared tunnel died.
            // bind_udp checks the adapter task locally without opening a phone service.
            let closed = adapter.bind_udp(0).await.is_err();
            let not_sent = error.is::<NotSent>();
            // Only a closed adapter is a dead tunnel. A live one stays, since a cellular replacement may be refused.
            if closed {
                self.connection = None;
                if (not_sent || action.read_only()) && !fresh {
                    continue;
                }
            }
            if not_sent || (closed && action.read_only()) {
                return unsent_reply(&action, error);
            }
            // Delivery can be ambiguous: the caller must inspect, never replay automatically.
            if local_read {
                return Err(error);
            }
            return Err(format!(
                "{error}. Input may have been delivered; inspect the screen before retrying."
            )
            .into());
        }
    }

    async fn open(&mut self) -> Result<()> {
        let connected = match tokio::time::timeout(Duration::from_secs(25), self.connect()).await {
            Ok(connected) => connected,
            Err(timeout) => Err(timeout.into()),
        };
        if connected.is_err() {
            self.control = None;
        }
        connected
    }
}

// The reply for a request whose input never reached the phone.
fn unsent_reply(
    action: &Request,
    error: Box<dyn std::error::Error + Send + Sync>,
) -> Result<Value> {
    match action {
        Request::LaunchApp(_) => Ok(super::apps::not_sent(error)),
        Request::Configuration { .. } => Err(error),
        action if action.read_only() => Err(error),
        _ => Ok(
            json!({"isError":true,"outcome":"not_sent","stop_reason":"error","sent":false,"screen_change_verified":false,"error":error.to_string(),"instruction":"Nothing reached the iPhone. Keep it connected and unlocked, then retry."}),
        ),
    }
}

fn load(path: &str) -> Result<Session> {
    Ok(Session {
        transport: Transport::Remote(serde_json::from_slice(&std::fs::read(path)?)?),
        control: None,
        connection: None,
    })
}

async fn reply(session: &mut Session, line: &str) -> Value {
    let response = if line.len() > 2 * 1024 * 1024 {
        Err("Remote request exceeds size limit".into())
    } else {
        match serde_json::from_str::<Value>(line) {
            Ok(request) => session.request(request).await,
            Err(e) => Err(e.into()),
        }
    };
    response.unwrap_or_else(|e| json!({"isError":true,"transport_error":true,"error":e.to_string(),"screen_change_verified":false}))
}

pub async fn serve(path: &str) -> Result<Value> {
    let mut session = load(path)?;
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    while let Some(line) = lines.next_line().await? {
        println!("{}", reply(&mut session, &line).await);
        std::io::stdout().flush()?;
    }
    let _ = session.release_input().await;
    Ok(json!({"closed":true}))
}

pub async fn serve_socket(path: &str, socket_path: &str) -> Result<Value> {
    serve_session(load(path)?, socket_path).await
}

pub async fn serve_local(udid: &str, socket_path: &str) -> Result<Value> {
    // EOF means the owning daemon is gone, including crashes without a shutdown hook.
    let owned_path = socket_path.to_owned();
    tokio::spawn(async move {
        use tokio::io::AsyncReadExt;
        let mut byte = [0u8; 1];
        let _ = tokio::io::stdin().read(&mut byte).await;
        let _ = std::fs::remove_file(owned_path);
        std::process::exit(0);
    });
    serve_session(
        Session {
            transport: Transport::Local(udid.into()),
            control: None,
            connection: None,
        },
        socket_path,
    )
    .await
}

async fn serve_session(mut session: Session, socket_path: &str) -> Result<Value> {
    use std::os::unix::fs::PermissionsExt;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let listener = tokio::net::UnixListener::bind(socket_path)?;
    std::fs::set_permissions(socket_path, std::fs::Permissions::from_mode(0o600))?;
    println!("{}", json!({"ready":true}));
    std::io::stdout().flush()?;
    loop {
        let (mut socket, _) = listener.accept().await?;
        let hello = format!("{}\n", json!({"pid":std::process::id()}));
        if socket.write_all(hello.as_bytes()).await.is_err() {
            continue;
        }
        let mut stream = BufReader::new(socket);
        let mut line = String::new();
        // The local directory is private. Bound incomplete requests so an abandoned client cannot hold the device.
        if !matches!(tokio::time::timeout(Duration::from_secs(5), (&mut stream).take(2 * 1024 * 1024 + 1).read_line(&mut line)).await, Ok(Ok(n)) if n > 0)
        {
            continue;
        }
        if line.len() > 2 * 1024 * 1024 {
            continue;
        }
        if serde_json::from_str::<Value>(&line)
            .ok()
            .is_some_and(|v| v["op"] == "disconnect")
        {
            stream
                .get_mut()
                .write_all(b"{\"disconnected\":true}\n")
                .await?;
            break;
        }
        let request = serde_json::from_str::<Request>(&line);
        let screenshot_path = match &request {
            Ok(Request::Screenshot { path }) => Some(path),
            _ => None,
        };
        let read_only = request.as_ref().is_ok_and(Request::read_only);
        let mut byte = [0u8; 1];
        let (output, abandoned) = if read_only {
            // Draining an observation preserves service framing when its caller stops waiting.
            let response = reply(&mut session, &line);
            tokio::pin!(response);
            tokio::select! {
                biased;
                _ = stream.read(&mut byte) => (response.await, true),
                output = &mut response => (output, false),
            }
        } else {
            let result = tokio::select! {
                biased;
                _ = stream.read(&mut byte) => None,
                output = reply(&mut session, &line) => Some(output),
            };
            match result {
                Some(output) => (output, false),
                None => {
                    let _ = session.release_input().await;
                    continue;
                }
            }
        };
        let mut bytes = serde_json::to_vec(&output)?;
        bytes.push(b'\n');
        let delivered = !abandoned && stream.get_mut().write_all(&bytes).await.is_ok();
        if !delivered && output["saved"] == true {
            if let Some(path) = screenshot_path {
                let _ = tokio::fs::remove_file(path).await;
            }
        }
    }
    let _ = session.release_input().await;
    let _ = std::fs::remove_file(socket_path);
    Ok(json!({"closed":true}))
}

#[cfg(test)]
mod tests {
    use super::*;
    use idevice::{
        ReadWrite, RsdService as _,
        core_device::{AppServiceClient, DisplayServiceClient},
        rsd::RsdService,
    };
    use std::{cell::RefCell, collections::HashMap};
    use tokio::{
        io::{AsyncReadExt, DuplexStream},
        sync::mpsc,
    };

    thread_local! {
        // Receives the phone end of every tunnel the session builds.
        static PHONE: RefCell<Option<mpsc::UnboundedSender<DuplexStream>>> = const { RefCell::new(None) };
    }

    fn tunnel() -> (Connection, DuplexStream) {
        let (host, phone) = tokio::io::duplex(1 << 16);
        let adapter = idevice::tcp::adapter::Adapter::new(
            Box::new(host),
            "fd00::1".parse().unwrap(),
            "fd00::2".parse().unwrap(),
        )
        .to_async_handle();
        let services = [
            DisplayServiceClient::<Box<dyn ReadWrite>>::rsd_service_name().to_string(),
            AppServiceClient::<Box<dyn ReadWrite>>::rsd_service_name().to_string(),
            "com.apple.accessibility.axAuditDaemon.remoteAXService".to_string(),
        ]
        .into_iter()
        .zip(50000u16..)
        .map(|(name, port)| {
            let service = RsdService {
                entitlement: String::new(),
                port,
                uses_remote_xpc: true,
                features: None,
                service_version: None,
            };
            (name, service)
        })
        .collect();
        let rsd = RsdHandshake {
            services,
            protocol_version: 2,
            properties: HashMap::new(),
            uuid: String::new(),
        };
        let connection = Connection {
            adapter,
            rsd,
            provider: None,
            media: None,
        };
        (connection, phone)
    }

    pub(super) async fn connect_local(_udid: &str) -> Result<Connection> {
        let (connection, phone) = tunnel();
        PHONE.with(|sender| sender.borrow().as_ref().map(|sender| sender.send(phone)));
        Ok(connection)
    }

    // A cable pulled while the helper idles: the tunnel's stream ends and its adapter task exits.
    async fn unplugged() -> Connection {
        let (connection, phone) = tunnel();
        drop(phone);
        while connection.adapter.bind_udp(0).await.is_ok() {}
        connection
    }

    #[tokio::test]
    async fn first_request_after_replug_rebuilds_the_tunnel_and_never_claims_delivery() {
        let mut failures = Vec::new();
        for request in [
            json!({"op":"tap","x":100,"y":200}),
            json!({"op":"launch_app","bundle_id":"local.fixture"}),
            json!({"op":"ax_tree"}),
        ] {
            let (sender, mut phones) = mpsc::unbounded_channel();
            PHONE.with(|slot| *slot.borrow_mut() = Some(sender));
            // The rebuilt tunnel carries the request's first packet; then the phone is gone again.
            let reached = tokio::spawn(async move {
                let mut reached = false;
                while let Some(mut phone) = phones.recv().await {
                    let mut byte = [0u8; 1];
                    reached |= phone.read(&mut byte).await.is_ok_and(|n| n > 0);
                }
                reached
            });
            let mut session = Session {
                transport: Transport::Local("fixture-phone".into()),
                control: None,
                connection: Some(unplugged().await),
            };
            let reply = session.request(request.clone()).await;
            PHONE.with(|slot| slot.borrow_mut().take());
            if !reached.await.unwrap() {
                failures.push(format!(
                    "{request}: did not rebuild the tunnel; reply: {reply:?}"
                ));
            }
            let reported = match (request["op"].as_str().unwrap(), &reply) {
                ("ax_tree", Err(error)) => !error.to_string().contains("delivered"),
                ("tap", Ok(reply)) => {
                    reply["outcome"] == "not_sent" && reply["stop_reason"] == "error"
                }
                ("launch_app", Ok(reply)) => reply["outcome"] == "not_sent",
                _ => false,
            };
            if !reported {
                failures.push(format!(
                    "{request}: nothing was sent, but the reply is {reply:?}"
                ));
            }
        }
        assert!(failures.is_empty(), "{}", failures.join("\n"));
    }

    #[tokio::test]
    async fn a_service_refused_on_a_live_tunnel_keeps_that_tunnel() {
        let (sender, mut phones) = mpsc::unbounded_channel();
        PHONE.with(|slot| *slot.borrow_mut() = Some(sender));
        // The adapter is alive, but the phone offers no display service, so opening it fails before any input.
        let (mut live, _phone) = tunnel();
        live.rsd.services.clear();
        live.rsd.uuid = "live tunnel".into();
        let mut session = Session {
            transport: Transport::Local("fixture-phone".into()),
            control: None,
            connection: Some(live),
        };
        let reply = session.request(json!({"op":"tap","x":100,"y":200})).await;
        PHONE.with(|slot| slot.borrow_mut().take());
        let reply = reply.expect("a refused service is a reply, not a transport error");
        assert_eq!(reply["outcome"], "not_sent", "{reply}");
        assert_eq!(reply["stop_reason"], "error", "{reply}");
        assert!(phones.recv().await.is_none(), "a live tunnel was rebuilt");
        let kept = session
            .connection
            .as_ref()
            .expect("the live tunnel was dropped");
        assert_eq!(kept.rsd.uuid, "live tunnel");
        assert!(kept.adapter.bind_udp(0).await.is_ok());
    }
}
