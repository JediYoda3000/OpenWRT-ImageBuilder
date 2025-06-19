#!/bin/bash
#######################################################################################################################
# Enhanced OpenWRT Image Builder with hybrid input system
# Combines best of both worlds:
# - Simplified Y/N prompts
# - Traditional input for complex values
# - Preserves all original functionality
#######################################################################################################################

clear

# Text colors
LYELLOW='\033[0;93m'
LRED='\033[0;91m'
GREEN='\033[0;32m'
NC='\033[0m'

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${LRED}Please run as root/sudo${NC}" >&2
    exit 1
fi

# Install basic deps
echo -e "${GREEN}Installing dependencies...${NC}"
apt-get update -qq
apt-get install -qq -y wget sudo jq

#######################################################################################################################
# User Configuration
#######################################################################################################################

# Version detection
LATEST_VERSION=$(wget -qO- https://downloads.openwrt.org/releases/ | grep -oP 'href="\K[0-9]+\.[0-9]+\.[0-9]+(?=/")' | sort -V | tail -1)

# Default values
VERSION="$LATEST_VERSION"
TARGET="x86"
ARCH="64"
IMAGE_PROFILE="generic"
BUILD_LOG="$(pwd)/build.log"

# Base packages with UEFI/Btrfs support
BASE_PACKAGES="block-mount kmod-fs-btrfs btrfs-progs kmod-usb-storage kmod-usb-core \
luci luci-proto-wireguard luci-app-wireguard"

# Partition sizes
KERNEL_SIZE_DEFAULT=32
ROOT_SIZE_DEFAULT=512

#######################################################################################################################
# Input Functions
#######################################################################################################################

ask_yn() {
    local prompt="$1 (Y/n): "
    local default=${2:-Y}
    while true; do
        read -p "$prompt" answer
        case "${answer:-$default}" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer Y or N" ;;
        esac
    done
}

ask_value() {
    local prompt="$1"
    local default="$2"
    read -p "$prompt [$default]: " answer
    echo "${answer:-$default}"
}

#######################################################################################################################
# Main User Prompts
#######################################################################################################################

echo -e "${GREEN}=== OpenWRT Image Builder ===${NC}"

# Version selection
VERSION=$(ask_value "Enter OpenWRT version" "$LATEST_VERSION")

# UEFI/Btrfs configuration
UEFI_ENABLED=false
BTRFS_ENABLED=false
ask_yn "Enable UEFI support" && UEFI_ENABLED=true
ask_yn "Use Btrfs filesystem" && BTRFS_ENABLED=true

# Additional packages
echo -e "${LYELLOW}Base packages included:${NC} $BASE_PACKAGES"
EXTRA_PKGS=$(ask_value "Enter extra packages (space separated)")

# Network configuration
echo -e "${GREEN}=== Network Configuration ==="
NET_MODE=$(ask_value "LAN mode (static/dhcp)" "dhcp")

if [[ "$NET_MODE" == "static" ]]; then
    LAN_IP=$(ask_value "LAN IP address" "192.168.1.1")
    LAN_GATEWAY=$(ask_value "Gateway" "192.168.1.1")
    LAN_DNS=$(ask_value "DNS server" "8.8.8.8")
fi

# Partition configuration
echo -e "${GREEN}=== Partition Configuration ==="
if ask_yn "Customize partition sizes"; then
    KERNEL_SIZE=$(ask_value "Kernel partition size (MB)" "$KERNEL_SIZE_DEFAULT")
    ROOT_SIZE=$(ask_value "Root partition size (MB)" "$ROOT_SIZE_DEFAULT")
fi

# VM conversion
CREATE_VM=false
ask_yn "Create VMware image" && CREATE_VM=true

#######################################################################################################################
# Build Configuration
#######################################################################################################################

# Prepare package list
CUSTOM_PACKAGES="$BASE_PACKAGES $EXTRA_PKGS"
if $BTRFS_ENABLED; then
    CUSTOM_PACKAGES+=" kmod-fs-btrfs btrfs-progs"
fi

# Builder URL
BUILDER_URL="https://downloads.openwrt.org/releases/${VERSION}/targets/${TARGET}/${ARCH}/openwrt-imagebuilder-${VERSION}-${TARGET}-${ARCH}.Linux-x86_64.tar.zst"

# Prepare directories
BUILD_ROOT="$(pwd)/openwrt_build_${VERSION}"
OUTPUT_DIR="$BUILD_ROOT/firmware"
WORK_DIR="$BUILD_ROOT/custom_files"

echo -e "${GREEN}=== Build Configuration ==="
echo -e "Version: ${LYELLOW}${VERSION}${NC}"
echo -e "Profile: ${LYELLOW}${IMAGE_PROFILE}${NC}"
echo -e "UEFI: ${LYELLOW}${UEFI_ENABLED}${NC}"
echo -e "Btrfs: ${LYELLOW}${BTRFS_ENABLED}${NC}"
echo -e "Packages: ${LYELLOW}${CUSTOM_PACKAGES}${NC}"
[[ "$NET_MODE" == "static" ]] && echo -e "Network: ${LYELLOW}IP:${LAN_IP} GW:${LAN_GATEWAY} DNS:${LAN_DNS}${NC}"
echo -e "Output: ${LYELLOW}${OUTPUT_DIR}${NC}"

#######################################################################################################################
# Build Execution
#######################################################################################################################

# Prepare environment
echo -e "${GREEN}Preparing build environment...${NC}"
rm -rf "$BUILD_ROOT"
mkdir -p {"$OUTPUT_DIR","$WORK_DIR"}

# Download and extract builder
echo -e "${GREEN}Downloading image builder...${NC}"
wget -q --show-progress "$BUILDER_URL" -O openwrt-builder.tar.zst
tar -xaf openwrt-builder.tar.zst
cd openwrt-imagebuilder-*

# Configure UEFI
if $UEFI_ENABLED; then
    echo -e "${GREEN}Configuring UEFI support...${NC}"
    cat >> .config <<EOF
CONFIG_EFI_IMAGES=y
CONFIG_GRUB_IMAGES=y
CONFIG_GRUB_EFI_IMAGES=y
EOF
fi

# Configure Btrfs
if $BTRFS_ENABLED; then
    echo -e "${GREEN}Configuring Btrfs support...${NC}"
    cat >> .config <<EOF
CONFIG_TARGET_ROOTFS_BTRFS=y
CONFIG_PACKAGE_btrfs-progs=y
EOF
fi

# Configure network
if [[ "$NET_MODE" == "static" ]]; then
    mkdir -p "$WORK_DIR/etc/uci-defaults"
    cat > "$WORK_DIR/etc/uci-defaults/99-network" <<EOF
uci set network.lan.proto='static'
uci set network.lan.ipaddr='${LAN_IP}'
uci set network.lan.gateway='${LAN_GATEWAY}'
uci set network.lan.dns='${LAN_DNS}'
uci commit
EOF
fi

# Start build
echo -e "${GREEN}Starting build process...${NC}"
make image PROFILE="$IMAGE_PROFILE" \
    PACKAGES="$CUSTOM_PACKAGES" \
    FILES="$WORK_DIR" \
    BIN_DIR="$OUTPUT_DIR" \
    ${KERNEL_SIZE:+CONFIG_TARGET_KERNEL_PARTSIZE=$KERNEL_SIZE} \
    ${ROOT_SIZE:+CONFIG_TARGET_ROOTFS_PARTSIZE=$ROOT_SIZE} 2>&1 | tee "$BUILD_LOG"

# VM conversion if requested
if $CREATE_VM; then
    echo -e "${GREEN}Creating VMware image...${NC}"
    for img in "$OUTPUT_DIR"/*.img; do
        qemu-img convert -f raw -O vmdk "$img" "${img%.*}.vmdk"
    done
fi

echo -e "${GREEN}=== Build Complete ==="
echo -e "Output files in: ${LYELLOW}${OUTPUT_DIR}${NC}"
ls -lh "$OUTPUT_DIR"
