#!/bin/bash
set -euo pipefail

serie_VERSION=$1
BUILD_VERSION=$2

if [ -z "$serie_VERSION" ] || [ -z "$BUILD_VERSION" ]; then
    echo "Usage: $0 <serie_version> <build_version>"
    echo "Example: $0 0.8.1 1"
    exit 1
fi

PACKAGE_NAME="serie"
ORIG_TARBALL="${PACKAGE_NAME}_${serie_VERSION}.orig.tar.gz"
BUILD_DIR="${PACKAGE_NAME}-${serie_VERSION}"

echo "Creating Debian/Ubuntu source packages for serie ${serie_VERSION}-${BUILD_VERSION}..."

# Download upstream source tarball (shared .orig.tar.gz across all distributions).
# Used as-is: the GitHub archive of tag v<version> extracts as serie-<version>/,
# which already matches BUILD_DIR, so no repacking is needed and the tarball
# stays byte-identical across rebuilds.
if [ ! -f "$ORIG_TARBALL" ]; then
    echo "Downloading upstream source from GitHub..."
    wget -q "https://github.com/lusingander/serie/archive/refs/tags/v${serie_VERSION}.tar.gz" -O "$ORIG_TARBALL"
    echo "  Downloaded $ORIG_TARBALL"
else
    echo "  Using existing $ORIG_TARBALL"
fi

build_source_package() {
    local dist=$1
    local FULL_VERSION="${serie_VERSION}-${BUILD_VERSION}~${dist}"

    echo "  Building source package for ${dist} (${FULL_VERSION})..."

    # Clean and recreate build directory from orig tarball
    rm -rf "$BUILD_DIR"
    tar -xf "$ORIG_TARBALL"
    # GitHub archives extract as serie-0.x.y/ which matches our BUILD_DIR

    # Copy Debian packaging directory
    cp -r debian "$BUILD_DIR/"

    # Generate distribution-specific changelog (overwrites placeholder)
    cat > "$BUILD_DIR/debian/changelog" << EOC
serie (${FULL_VERSION}) ${dist}; urgency=medium

  * New upstream release ${serie_VERSION}.

 -- Dario Griffo <dariogriffo@gmail.com>  $(date -R)
EOC

    # Build source package (.dsc + .debian.tar.xz); reuses existing .orig.tar.gz
    dpkg-source -b "$BUILD_DIR"

    rm -rf "$BUILD_DIR"
    echo "    ${FULL_VERSION}"
}

echo ""
echo "Building Debian source packages..."
DEBIAN_DISTS=("bookworm" "trixie" "forky" "sid")
for dist in "${DEBIAN_DISTS[@]}"; do
    build_source_package "$dist"
done

echo ""
echo "Building Ubuntu source packages..."
UBUNTU_DISTS=("jammy" "noble" "questing" "resolute")
for dist in "${UBUNTU_DISTS[@]}"; do
    build_source_package "$dist"
done

echo ""
echo "Source packages created successfully!"
echo ""
echo "Generated files:"
ls -la "${PACKAGE_NAME}_"*.dsc "${PACKAGE_NAME}_"*.orig.tar.gz "${PACKAGE_NAME}_"*.debian.tar.xz 2>/dev/null || true
