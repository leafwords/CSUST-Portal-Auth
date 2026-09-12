#!/bin/sh
set -eu

OPENWRT_VERSION="${OPENWRT_VERSION:-24.10.5}"
SDK_ARCH="${SDK_ARCH:-x86-64}"
SDK_BASENAME="openwrt-sdk-${OPENWRT_VERSION}-${SDK_ARCH}_gcc-13.3.0_musl.Linux-x86_64"
SDK_ARCHIVE="${SDK_BASENAME}.tar.zst"
SDK_URL="${SDK_URL:-https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/x86/64/${SDK_ARCHIVE}}"
SDK_SHA256="${SDK_SHA256:-d3e8ea62fc1c12f93a9c808c2ef4c01b6e149ee240bcd5a74d15bebcbc385bdd}"

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CACHE_DIR="${CACHE_DIR:-$ROOT_DIR/work}"
WORK_DIR="${WORK_DIR:-/tmp/luci-app-campus-portal-ipk-sdk}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/outputs}"
SDK_DIR="$WORK_DIR/$SDK_BASENAME"

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

if [ ! -f "$WORK_DIR/$SDK_ARCHIVE" ] && [ -f "$CACHE_DIR/$SDK_ARCHIVE" ]; then
	echo "Reusing cached $SDK_ARCHIVE"
	cp "$CACHE_DIR/$SDK_ARCHIVE" "$WORK_DIR/$SDK_ARCHIVE"
fi

if [ ! -f "$WORK_DIR/$SDK_ARCHIVE" ]; then
	echo "Downloading $SDK_ARCHIVE"
	curl -fL --retry 3 --output "$WORK_DIR/$SDK_ARCHIVE" "$SDK_URL"
fi

if [ -n "$SDK_SHA256" ]; then
	echo "$SDK_SHA256  $WORK_DIR/$SDK_ARCHIVE" | sha256sum -c -
fi

if [ ! -d "$SDK_DIR" ]; then
	echo "Extracting SDK"
	tar --zstd -xf "$WORK_DIR/$SDK_ARCHIVE" -C "$WORK_DIR"
fi

PACKAGE_DIR="$SDK_DIR/package/luci-app-campus-portal"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

cp "$ROOT_DIR/Makefile" "$PACKAGE_DIR/"
cp "$ROOT_DIR/README.md" "$PACKAGE_DIR/"
cp "$ROOT_DIR/LICENSE" "$PACKAGE_DIR/"
cp -a "$ROOT_DIR/files" "$PACKAGE_DIR/"

echo "Building IPK"
make -C "$SDK_DIR" defconfig
make -C "$SDK_DIR" package/luci-app-campus-portal/compile V=s -j"$(nproc)"

IPK_FILE="$(find "$SDK_DIR/bin/packages" -type f -name 'luci-app-campus-portal_*.ipk' | head -n 1)"

if [ -z "$IPK_FILE" ]; then
	echo "Build succeeded but no IPK was found" >&2
	exit 1
fi

cp "$IPK_FILE" "$OUTPUT_DIR/"
echo "IPK: $OUTPUT_DIR/$(basename "$IPK_FILE")"
