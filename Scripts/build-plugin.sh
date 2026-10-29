#!/bin/sh
# Builds plugins/<name>/Plugin, packages it as plugins/<name>/releases/<version>/<Product>.ruyioplugin.zip
# (app + the same manifest.json it embeds) and records the release with its SHA-256 in
# plugins/<name>/ruyio-plugin.json. A published version must never point to a different file, so an
# existing package is only replaced with --replace, before that version is pushed.
#
# The app is signed with the publisher's certificate: Ruyio installs market packages only with a certificate
# signature, and a self-signed one, created here on first use, is enough. Updates must carry the same
# certificate, so keep its keychain (default ~/Library/Keychains/ruyio-plugin-publisher.keychain-db).
#
# Usage: Scripts/build-plugin.sh <name> [--replace]
# RUYIO_ROOT points at a Ruyio checkout for the plugin SDK (default: ../Ruyio next to this repository).
# RUYIO_PUBLISHER_KEYCHAIN / RUYIO_PUBLISHER_NAME choose another publisher identity.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:?usage: Scripts/build-plugin.sh <name> [--replace]}
PLUGIN="$ROOT/plugins/$NAME"
RUYIO_ROOT=$(cd "${RUYIO_ROOT:-$ROOT/../Ruyio}" && pwd)
export RUYIO_ROOT
PUBLISHER_KEYCHAIN=${RUYIO_PUBLISHER_KEYCHAIN:-$HOME/Library/Keychains/ruyio-plugin-publisher.keychain-db}
PUBLISHER_NAME=${RUYIO_PUBLISHER_NAME:-Ruyio Plugin Publisher}
. "$RUYIO_ROOT/Scripts/lib/signing-identity.sh"
SIGNER=$(ensure_signing_identity "$PUBLISHER_KEYCHAIN" "$PUBLISHER_NAME" 7300)
PUBLISHER="cert:$(certificate_sha256 "$PUBLISHER_KEYCHAIN" "$PUBLISHER_NAME")"

cd "$PLUGIN/Plugin"
field() { python3 -c "import json,sys; print(json.load(open('manifest.json'))[sys.argv[1]])" "$1"; }
BUNDLE=$(field bundlePath)
PRODUCT=${BUNDLE%.app}
VERSION=$(field version)
OUT="$PLUGIN/releases/$VERSION/$PRODUCT.ruyioplugin.zip"
if [ -e "$OUT" ] && [ "${2:-}" != "--replace" ]; then
  echo "error: $OUT exists; bump the version, or pass --replace if $VERSION was never pushed" >&2
  exit 1
fi

mkdir -p build
xcodegen generate --quiet
xcodebuild -project "$PRODUCT.xcodeproj" -scheme "$PRODUCT" -configuration Release -derivedDataPath build/DerivedData -quiet build
APP="build/DerivedData/Build/Products/Release/$BUNDLE"
with_signing_keychain "$PUBLISHER_KEYCHAIN" codesign --force --sign "$SIGNER" --keychain "$PUBLISHER_KEYCHAIN" \
  --preserve-metadata=entitlements,flags,runtime --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/$PRODUCT.ruyioplugin"
ditto "$APP" "$WORK/$PRODUCT.ruyioplugin/$BUNDLE"
cp manifest.json "$WORK/$PRODUCT.ruyioplugin/manifest.json"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
(cd "$WORK" && ditto -c -k --sequesterRsrc --keepParent "$PRODUCT.ruyioplugin" "$OUT")
SHA=$(shasum -a 256 "$OUT" | cut -d' ' -f1)

python3 - "$PLUGIN/ruyio-plugin.json" "$VERSION" "releases/$VERSION/$PRODUCT.ruyioplugin.zip" "$SHA" <<'PY'
import json, os, sys
path, version, artifact, sha = sys.argv[1:]
manifest = json.load(open("manifest.json"))
descriptor = json.load(open(path)) if os.path.exists(path) else {"schemaVersion": 1, "kind": "plugin", "releases": []}
descriptor.update(id=manifest["id"], name=manifest["name"], description=manifest["description"], source=manifest["source"])
release = {"version": version, "minimumHostVersion": manifest["minimumHostVersion"],
           "minimumMacOSVersion": manifest["minimumMacOSVersion"], "architectures": manifest["architectures"],
           "artifact": artifact, "sha256": sha}
descriptor["releases"] = [r for r in descriptor["releases"] if r["version"] != version] + [release]
with open(path, "w") as f:
    json.dump(descriptor, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
echo "$PRODUCT $VERSION -> $OUT ($SHA), publisher $PUBLISHER"
