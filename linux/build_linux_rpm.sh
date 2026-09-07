#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/rpm"
TOPDIR="$BUILD_DIR/rpmbuild"
SOURCES_DIR="$TOPDIR/SOURCES"
SPECS_DIR="$TOPDIR/SPECS"
OUTPUT_DIR="$ROOT_DIR/build/dist"
RAW_VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$ROOT_DIR/pubspec.yaml" | head -n1)"
RPM_VERSION="$RAW_VERSION"
RPM_RELEASE="1%{?dist}"
RPM_ARTIFACT_NAME="vertree-linux-x64-$RAW_VERSION.rpm"
RELEASE_BUNDLE_DIR="$ROOT_DIR/build/linux/x64/release/bundle"
SOURCE_ROOT=""
SOURCE_TARBALL=""
RELEASE_DATE="$(date -u +%F)"
CHANGELOG_DATE="$(LC_ALL=C date -u '+%a %b %d %Y')"

if [[ -z "$RAW_VERSION" ]]; then
  echo "Unable to determine version from pubspec.yaml" >&2
  exit 1
fi

if [[ "$RAW_VERSION" == *-* ]]; then
  RPM_VERSION="${RAW_VERSION%%-*}"
  PRERELEASE="${RAW_VERSION#*-}"
  SAFE_PRERELEASE="${PRERELEASE//[^A-Za-z0-9.]/.}"
  RPM_RELEASE="0.1.${SAFE_PRERELEASE}%{?dist}"
fi

SOURCE_ROOT="$BUILD_DIR/vertree-$RPM_VERSION"
SOURCE_TARBALL="$SOURCES_DIR/vertree-$RPM_VERSION.tar.gz"

export PATH="$HOME/.local/flutter/bin:$PATH"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"

if [[ "${SKIP_FLUTTER_BUILD:-0}" != "1" ]]; then
  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
    flutter build linux --target lib/main.dart --release
fi

rm -rf "$TOPDIR" "$SOURCE_ROOT"
mkdir -p "$SOURCES_DIR" "$SPECS_DIR" "$SOURCE_ROOT" "$OUTPUT_DIR"

cp -a "$RELEASE_BUNDLE_DIR" "$SOURCE_ROOT/bundle"
cp "$ROOT_DIR/LICENSE" "$SOURCE_ROOT/LICENSE"
tar -C "$BUILD_DIR" -czf "$SOURCE_TARBALL" "vertree-$RPM_VERSION"

sed \
  -e "s/@RPM_VERSION@/$RPM_VERSION/g" \
  -e "s/@RPM_RELEASE@/$RPM_RELEASE/g" \
  -e "s/@RAW_VERSION@/$RAW_VERSION/g" \
  -e "s/@CHANGELOG_DATE@/$CHANGELOG_DATE/g" \
  "$ROOT_DIR/linux/packaging/vertree.spec" > "$SPECS_DIR/vertree.spec"
cp "$ROOT_DIR/linux/packaging/vertree.desktop" "$SOURCES_DIR/"
cp "$ROOT_DIR/assets/img/logo/logo.png" "$SOURCES_DIR/vertree.png"
cp "$ROOT_DIR/linux/packaging/vertree.sh" "$SOURCES_DIR/"
sed \
  -e "s/@VERSION@/$RAW_VERSION/g" \
  -e "s/@RELEASE_DATE@/$RELEASE_DATE/g" \
  "$ROOT_DIR/linux/packaging/vertree.metainfo.xml" > "$SOURCES_DIR/vertree.metainfo.xml"
cp "$ROOT_DIR/linux/packaging/vertree_nautilus.py" "$SOURCES_DIR/"

if command -v rpmbuild >/dev/null 2>&1; then
  rpmbuild --define "_topdir $TOPDIR" -bb "$SPECS_DIR/vertree.spec"
else
  if ! command -v podman >/dev/null 2>&1; then
    echo "Neither rpmbuild nor podman is available." >&2
    exit 1
  fi

  FEDORA_RELEASE_MIRROR="${FEDORA_RELEASE_MIRROR:-https://mirrors.ustc.edu.cn/fedora/releases/43/Everything/x86_64/os/}"
  FEDORA_UPDATES_MIRROR="${FEDORA_UPDATES_MIRROR:-https://mirrors.ustc.edu.cn/fedora/updates/43/Everything/x86_64/}"

  podman run --rm \
    --security-opt label=disable \
    -v "$ROOT_DIR:/src" \
    -w /src \
    registry.fedoraproject.org/fedora:43 \
    bash -lc "dnf -y --disablerepo='*' --repofrompath=vertree-fedora,$FEDORA_RELEASE_MIRROR --repofrompath=vertree-updates,$FEDORA_UPDATES_MIRROR install rpm-build desktop-file-utils appstream && rpmbuild --define '_topdir /src/build/rpm/rpmbuild' -bb /src/build/rpm/rpmbuild/SPECS/vertree.spec"
fi

RPM_BUILT_PATH="$(find "$TOPDIR/RPMS" -type f -name '*.rpm' | head -n1)"
if [[ -z "$RPM_BUILT_PATH" ]]; then
  echo "RPM build completed but no .rpm artifact was found under $TOPDIR/RPMS" >&2
  exit 1
fi

cp -f "$RPM_BUILT_PATH" "$OUTPUT_DIR/$RPM_ARTIFACT_NAME"

echo "RPMs are available under: $TOPDIR/RPMS"
