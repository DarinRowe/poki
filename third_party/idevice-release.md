# idevice in the prebuilt package

The prebuilt package uses the idevice revision pinned in `bin/setup`. Its MIT license is included at `native/bridge/LICENSE.idevice`.

The upstream `tools/src/installcoordination_proxy.rs` contains an absolute developer-home path for a diagnostic packet capture. The release build replaces that string with `/tmp/idevice-capture.pcap`. This affects only the upstream `installcoordination_proxy` diagnostic command's capture destination. Poki uses its own native InstallationProxy implementation. Other upstream code is unchanged.

To reproduce this replacement after obtaining the pinned source, run from the repository root:

```sh
python3 - <<'PY'
from pathlib import Path
import re
path = Path('.deps/idevice/tools/src/installcoordination_proxy.rs')
text = path.read_text()
text, count = re.subn(r'/Users/[^"\s]+\.pcap', '/tmp/idevice-capture.pcap', text)
if count != 1:
    raise SystemExit('Expected one upstream diagnostic capture path')
path.write_text(text)
PY
```

Build the native executables with path remapping. Keep the repository mapping last so it takes precedence over broader mappings:

```sh
export RUSTFLAGS="--remap-path-prefix=$HOME=/builder --remap-path-prefix=/Volumes=/build --remap-path-prefix=$PWD=/poki"
export CFLAGS="-ffile-prefix-map=$HOME=/builder -ffile-prefix-map=/Volumes=/build -ffile-prefix-map=$PWD=/poki"
export CXXFLAGS="$CFLAGS"
export MACOSX_DEPLOYMENT_TARGET=15.0
./bin/build-native
cargo build --locked --release --manifest-path native/bridge/Cargo.toml --target-dir build/native-target --example unlock_iphone -j 4
cargo build --locked --release --manifest-path .deps/idevice/Cargo.toml --target-dir build/idevice-target -p idevice-tools --bin idevice-tools --bin idevice_id -j 4
```

The package keeps `idevice-tools` and `idevice_id` in `.deps/idevice/target/release/`, and the unlock helper in `build/native-target/release/examples/`. The other native executables are in `build/`. Node.js, FFmpeg, and npm packages are installed separately as described in the README.

The package does not embed sharp or libvips binaries. `npm ci` installs the locked upstream packages with their licenses. Keep those licenses when redistributing an installed tree, including the libvips LGPL terms, component notices, and corresponding source requirements. The package retains `third_party/NOTICE.sharp-libvips.md` and the source inventory in `docs/third-party-dependencies.md`.
