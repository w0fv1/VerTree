#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/build/dist"
STAGE_DIR="$DIST_DIR/vertree-linux-x64"
VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$ROOT_DIR/pubspec.yaml" | head -n1)"
RELEASE_BUNDLE_DIR="$ROOT_DIR/build/linux/x64/release/bundle"
ARCHIVE_PATH="$DIST_DIR/vertree-linux-x64-$VERSION.tar.gz"

if [[ -z "$VERSION" ]]; then
  echo "Unable to determine version from pubspec.yaml" >&2
  exit 1
fi

export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"

if [[ "${SKIP_FLUTTER_BUILD:-0}" != "1" ]]; then
  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
    flutter build linux --target lib/main.dart --release
fi

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$DIST_DIR"

cp -a "$RELEASE_BUNDLE_DIR" "$STAGE_DIR/bundle"
cp "$ROOT_DIR/linux/packaging/vertree.desktop" "$STAGE_DIR/dev.w0fv1.vertree.desktop"
cp "$ROOT_DIR/linux/packaging/vertree.metainfo.xml" "$STAGE_DIR/dev.w0fv1.vertree.metainfo.xml"
cp "$ROOT_DIR/linux/packaging/vertree_nautilus.py" "$STAGE_DIR/vertree_nautilus.py"
cp "$ROOT_DIR/assets/img/logo/logo.png" "$STAGE_DIR/vertree.png"

cat > "$STAGE_DIR/vertree" <<'EOF'
#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/bundle/vertree" "$@"
EOF
chmod +x "$STAGE_DIR/vertree"

sed -i "s/@VERSION@/$VERSION/g" "$STAGE_DIR/dev.w0fv1.vertree.metainfo.xml"
sed -i "s/@RELEASE_DATE@/$(date -u +%F)/g" "$STAGE_DIR/dev.w0fv1.vertree.metainfo.xml"

tar -C "$DIST_DIR" -czf "$ARCHIVE_PATH" "$(basename "$STAGE_DIR")"

echo "Linux release archive created: $ARCHIVE_PATH"
