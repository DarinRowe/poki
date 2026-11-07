#!/bin/bash
# Package an unsigned build. Stamp every extension in the staging copy, never the build products.
set -euo pipefail
if [ "$#" != 5 ]; then
  echo "Usage: package-app.sh Poki.app local|external output.ipa version build" >&2
  exit 2
fi
app="$1"; edition="$2"; output="$3"; version="$4"; build="$5"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/Payload"
ditto "$app" "$stage/Payload/Poki.app"
python3 - "$stage/Payload/Poki.app" "$edition" "$version" "$build" <<'PY'
import pathlib, plistlib, sys
app, edition, version, build = pathlib.Path(sys.argv[1]), *sys.argv[2:]
if edition not in ('local', 'external'):
    raise SystemExit('Expected local or external connection edition')
extensions = {p.name for p in (app / 'PlugIns').glob('*.appex')}
expected = {'PokiWidgets.appex'} | ({'PokiTunnel.appex'} if edition == 'local' else set())
if extensions != expected:
    raise SystemExit(f'Wrong extensions for {edition}: {sorted(extensions)}')
if edition == 'local':
    with (app / 'PlugIns/PokiTunnel.appex/Info.plist').open('rb') as f:
        extension = plistlib.load(f).get('NSExtension', {})
    if extension.get('NSExtensionPointIdentifier') != 'com.apple.networkextension.packet-tunnel':
        raise SystemExit('Missing packet-tunnel extension point')
    if extension.get('NSExtensionPrincipalClass') != 'PokiTunnel.PacketTunnelProvider':
        raise SystemExit('Wrong packet-tunnel entry point')
for bundle in [app, *(app / 'PlugIns').glob('*.appex')]:
    path = bundle / 'Info.plist'
    with path.open('rb') as f:
        info = plistlib.load(f)
    info['CFBundleShortVersionString'] = version
    info['CFBundleVersion'] = build
    with path.open('wb') as f:
        plistlib.dump(info, f)
print(f'{edition}: app and {len(extensions)} extensions, version {version} ({build})')
PY
mkdir -p "$(dirname "$output")"
ditto -c -k --keepParent --norsrc "$stage/Payload" "$output"
