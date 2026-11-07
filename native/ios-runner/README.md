# Poki runner (on-phone)

The runner is the part of Poki that runs on the iPhone itself: Appium's WebDriverAgent (BSD-3-Clause,
vendored as a submodule at `WebDriverAgent/`, pinned to v16.15.3, commit `02cb92f0`), built as the
`WebDriverAgentRunner` UI-test host and branded as Poki Runner (its own icon from `docs/images/runner/`, display name, launch screen) by
`branding/brand.sh`.

## Build

There is one build path: the GitHub Actions workflow `.github/workflows/ios-runner.yml` on macOS. It
runs `xcodebuild build-for-testing` for the iOS device SDK with signing off, brands the app, strips
dSYMs and uploads two unsigned IPAs with their SHA-256 sums as the `poki-runner-unsigned` artifact:

- `poki-runner-unsigned.ipa` leaves out the XCTest libraries Xcode copies into the runner, as
  WebDriverAgent's own real-device package does; they come from the phone's developer image.
- `poki-runner-unsigned-with-frameworks.ipa` keeps them.

It runs on demand and for `ios-v*` release tags. The IPA is signed when it is installed (for
now AltStore with the user's Apple ID).

## Poki Probe

The probe (10.7.0.1 reachability and the background hold test) is now the Debug tab of the Poki app,
`native/ios-app/Poki/Debug/`.

## How Poki reaches the runner

The runner does not connect to the relay. PokiCore, inside the Poki app, dials the person's relay and
sends WebDriver requests to the runner at `127.0.0.1:8100` on the same phone. PokiLauncher starts the
runner through the phone's own developer services (`docs/ios-core.md`).

## Known issue: port 8100 is open to the local network

The launcher does not set WebDriverAgent's `USE_IP` (`native/launcher/src/launch.rs`), so WebDriverAgent
listens on port 8100 on every network interface of the phone, not only on 127.0.0.1. It asks for no
credentials. While the runner runs, any device on the same network can open `http://<phone IP>:8100`,
take screenshots and tap, and PokiCore's approvals do not apply to those requests. Turn Poki on only on
networks you trust.

The planned fix pairs the runner with Poki through a pairing code, so that only Poki can control it.

## Goals

**No unauthenticated control.** Only Poki may control the runner. The known issue above breaks this
rule today.

**Minimal third-party tools.** The end state is a store-distributable Poki companion app that installs
and refreshes the runner itself with the user's Apple ID (the SideStore / StikDebug approach) and
relaunches the runner after a reboot. A user needs only an Apple ID and Developer Mode. AltStore is a
stand-in until then.
