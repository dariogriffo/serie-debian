serie_VERSION=$1
BUILD_VERSION=$2
ARCH=${3:-amd64}  # Default to amd64 if no architecture specified

if [ -z "$serie_VERSION" ] || [ -z "$BUILD_VERSION" ]; then
    echo "Usage: $0 <serie_version> <build_version> [architecture]"
    echo "Example: $0 0.8.1 1 arm64"
    echo "Example: $0 0.8.1 1 all    # Build for all architectures"
    echo "Supported architectures: amd64, arm64, all"
    exit 1
fi

# Function to map Debian architecture to serie release name
# Upstream only publishes x86_64 and aarch64 Linux builds; we use the musl
# (statically linked) ones so a single binary works on every supported suite.
get_serie_release() {
    local arch=$1
    case "$arch" in
        "amd64")
            echo "serie-${serie_VERSION}-x86_64-unknown-linux-musl"
            ;;
        "arm64")
            echo "serie-${serie_VERSION}-aarch64-unknown-linux-musl"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Function to build for a specific architecture
build_architecture() {
    local build_arch=$1
    local serie_release

    serie_release=$(get_serie_release "$build_arch")
    if [ -z "$serie_release" ]; then
        echo "❌ Unsupported architecture: $build_arch"
        echo "Supported architectures: amd64, arm64"
        return 1
    fi

    echo "Building for architecture: $build_arch using $serie_release"

    # Clean up any previous builds for this architecture
    rm -rf "$serie_release" || true
    rm -f "${serie_release}.tar.gz" || true

    # Download and extract serie binary for this architecture
    if ! wget "https://github.com/lusingander/serie/releases/download/v${serie_VERSION}/${serie_release}.tar.gz"; then
        echo "❌ Failed to download serie binary for $build_arch"
        return 1
    fi

    # serie tarballs are flat (just the binary), extract into a per-release directory
    mkdir -p "$serie_release"
    if ! tar -xf "${serie_release}.tar.gz" -C "$serie_release"; then
        echo "❌ Failed to extract serie binary for $build_arch"
        return 1
    fi

    rm -f "${serie_release}.tar.gz"

    # Build packages for appropriate Debian distributions
    declare -a arr=("bookworm" "trixie" "forky" "sid")

    for dist in "${arr[@]}"; do
        FULL_VERSION="$serie_VERSION-${BUILD_VERSION}~${dist}_${build_arch}"
        echo "  Building $FULL_VERSION"

        if ! docker build . -t "serie-$dist-$build_arch" \
            --build-arg DEBIAN_DIST="$dist" \
            --build-arg serie_VERSION="$serie_VERSION" \
            --build-arg BUILD_VERSION="$BUILD_VERSION" \
            --build-arg FULL_VERSION="$FULL_VERSION" \
            --build-arg ARCH="$build_arch" \
            --build-arg SERIE_RELEASE="$serie_release"; then
            echo "❌ Failed to build Docker image for $dist on $build_arch"
            return 1
        fi

        id="$(docker create "serie-$dist-$build_arch")"
        if ! docker cp "$id:/serie_$FULL_VERSION.deb" - > "./serie_$FULL_VERSION.deb"; then
            echo "❌ Failed to extract .deb package for $dist on $build_arch"
            return 1
        fi

        if ! tar -xf "./serie_$FULL_VERSION.deb"; then
            echo "❌ Failed to extract .deb contents for $dist on $build_arch"
            return 1
        fi
    done

    # Clean up extracted directory
    rm -rf "$serie_release" || true

    echo "✅ Successfully built for $build_arch"
    return 0
}

# Main build logic
if [ "$ARCH" = "all" ]; then
    echo "🚀 Building serie $serie_VERSION-$BUILD_VERSION for all supported architectures..."
    echo ""

    # All supported architectures
    ARCHITECTURES=("amd64" "arm64")

    for build_arch in "${ARCHITECTURES[@]}"; do
        echo "==========================================="
        echo "Building for architecture: $build_arch"
        echo "==========================================="

        if ! build_architecture "$build_arch"; then
            echo "❌ Failed to build for $build_arch"
            exit 1
        fi

        echo ""
    done

    echo "🎉 All architectures built successfully!"
    echo "Generated packages:"
    ls -la serie_*.deb
else
    # Build for single architecture
    if ! build_architecture "$ARCH"; then
        exit 1
    fi
fi
