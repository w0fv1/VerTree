#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/build/dist"
BUILD_DIR="$ROOT_DIR/build/deb"
PKG_ROOT="$BUILD_DIR/pkgroot"
DEBIAN_DIR="$PKG_ROOT/DEBIAN"
RAW_VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$ROOT_DIR/pubspec.yaml" | head -n1)"
DEB_VERSION="$RAW_VERSION"
ARCH="$(dpkg --print-architecture)"
ARCH_ALIAS="x64"
RELEASE_BUNDLE_DIR="$ROOT_DIR/build/linux/x64/release/bundle"
PACKAGE_PATH="$DIST_DIR/vertree-linux-$ARCH_ALIAS-$RAW_VERSION.deb"
RELEASE_DATE="$(date -u +%F)"

if [[ -z "$RAW_VERSION" ]]; then
  echo "Unable to determine version from pubspec.yaml" >&2
  exit 1
fi

if [[ "$ARCH" == "arm64" ]]; then
  ARCH_ALIAS="arm64"
  PACKAGE_PATH="$DIST_DIR/vertree-linux-$ARCH_ALIAS-$RAW_VERSION.deb"
fi

if [[ "$RAW_VERSION" == *-* ]]; then
  DEB_VERSION="${RAW_VERSION%%-*}~${RAW_VERSION#*-}"
fi

export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"

if [[ "${SKIP_FLUTTER_BUILD:-0}" != "1" ]]; then
  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
    flutter build linux --target lib/main.dart --release
fi

rm -rf "$PKG_ROOT"
mkdir -p \
  "$DEBIAN_DIR" \
  "$PKG_ROOT/usr/libexec/vertree" \
  "$PKG_ROOT/usr/bin" \
  "$PKG_ROOT/usr/share/applications" \
  "$PKG_ROOT/usr/share/icons/hicolor/256x256/apps" \
  "$PKG_ROOT/usr/share/metainfo" \
  "$PKG_ROOT/usr/share/nautilus-python/extensions" \
  "$DIST_DIR"

cp -a "$RELEASE_BUNDLE_DIR/." "$PKG_ROOT/usr/libexec/vertree/"
install -m 0755 "$ROOT_DIR/linux/packaging/vertree.sh" "$PKG_ROOT/usr/bin/vertree"
install -m 0644 "$ROOT_DIR/linux/packaging/vertree.desktop" \
  "$PKG_ROOT/usr/share/applications/dev.w0fv1.vertree.desktop"
install -m 0644 "$ROOT_DIR/assets/img/logo/logo.png" \
  "$PKG_ROOT/usr/share/icons/hicolor/256x256/apps/vertree.png"
sed \
  -e "s/@VERSION@/$RAW_VERSION/g" \
  -e "s/@RELEASE_DATE@/$RELEASE_DATE/g" \
  "$ROOT_DIR/linux/packaging/vertree.metainfo.xml" \
  > "$PKG_ROOT/usr/share/metainfo/dev.w0fv1.vertree.metainfo.xml"
install -m 0644 "$ROOT_DIR/linux/packaging/vertree_nautilus.py" \
  "$PKG_ROOT/usr/share/nautilus-python/extensions/vertree_extension.py"

cat > "$DEBIAN_DIR/control" <<EOF
Package: vertree
Version: $DEB_VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: w0fv1 <wofbi1@outlook.com>
Depends: libc6 (>= 2.31), libstdc++6, libgtk-3-0
Recommends: nautilus-python
Homepage: https://vertree.w0fv1.dev
Description: Single-file version manager for backup, monitoring, and version trees
 Vertree is a desktop application for single-file version management.
 It supports manual backups, quick backups, file monitoring, and visual
 version tree inspection for files that do not fit a Git-based workflow.
EOF

cat > "$DEBIAN_DIR/postinst" <<'EOF'
#!/usr/bin/env sh
set -e

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
EOF

cat > "$DEBIAN_DIR/postrm" <<'EOF'
#!/usr/bin/env sh
set -e

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
EOF

chmod 0755 "$DEBIAN_DIR/postinst" "$DEBIAN_DIR/postrm"

rm -f "$PACKAGE_PATH"
dpkg-deb --build --root-owner-group "$PKG_ROOT" "$PACKAGE_PATH"

echo "DEB package created: $PACKAGE_PATH"
