#!/bin/bash
#######################################################################################################################
# Fixed OpenWRT Image Builder with dependency handling
# Fixes:
# - Added zstd support
# - Proper archive extraction
# - Better error handling
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

# Install all required dependencies
echo -e "${GREEN}Installing dependencies...${NC}"
apt-get update -qq
apt-get install -qq -y wget sudo jq zstd qemu-utils build-essential libncurses-dev \
libssl-dev python3-distutils rsync unzip zlib1g-dev file

#######################################################################################################################
# Fixed Build Functions
#######################################################################################################################

download_builder() {
    local url="$1"
    echo -e "${GREEN}Downloading image builder...${NC}"
    if ! wget -q --show-progress "$url" -O openwrt-builder.tar.zst; then
        echo -e "${LRED}Failed to download builder!${NC}"
        exit 1
    fi
}

extract_builder() {
    echo -e "${GREEN}Extracting image builder...${NC}" >&2  # Добавлено >&2 для вывода в stderr
    if ! tar -I zstd -xaf openwrt-builder.tar.zst; then
        echo -e "${LRED}Failed to extract builder!${NC}" >&2
        exit 1
    fi
    
    local builder_dir=$(find . -maxdepth 1 -type d -name 'openwrt-imagebuilder-*' | head -1)
    if [[ -z "$builder_dir" ]]; then
        echo -e "${LRED}Could not find extracted builder directory!${NC}" >&2
        exit 1
    fi
    echo "$builder_dir"  # Выводим только имя директории без цветовых кодов
}

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
# Обновленные базовые пакеты
BASE_PACKAGES="blockd block-mount kmod-fs-ext4 kmod-usb2 kmod-usb3 kmod-usb-storage kmod-usb-core usbutils \
dnsmasq-full luci luci-app-pbr \
luci-app-ksmbd luci-app-sqm sqm-scripts sqm-scripts-extra luci-app-attendedsysupgrade \
curl nano socat tcpdump python3-light python3-netifaces wsdd2 igmpproxy iptables-mod-ipopt \
usbmuxd libimobiledevice kmod-usb-net kmod-usb-net-asix-ax88179 kmod-mt7921u kmod-usb-net-rndis kmod-usb-net-ipheth \
byobu zsh blkid tmux screen cfdisk resize2fs git git-http htop losetup luci-app-dockerman luci-app-ttyd luci-i18n-base-ru luci-proto-wireguard luci-app-wireguard vim"

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
download_builder "$BUILDER_URL"
BUILDER_DIR=$(extract_builder)
cd "$BUILDER_DIR" || exit 1

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
{
    # Первая попытка сборки с полным набором пакетов
    make V=s -j1 image PROFILE="$IMAGE_PROFILE" \
        PACKAGES="$CUSTOM_PACKAGES" \
        FILES="$WORK_DIR" \
        BIN_DIR="$OUTPUT_DIR" \
        ${KERNEL_SIZE:+CONFIG_TARGET_KERNEL_PARTSIZE=$KERNEL_SIZE} \
        ${ROOT_SIZE:+CONFIG_TARGET_ROOTFS_PARTSIZE=$ROOT_SIZE} 2>&1 | tee "$BUILD_LOG"
} || {
    echo -e "${LRED}First build attempt failed, analyzing errors...${NC}"
    
    # Анализ лога для поиска проблемных пакетов
    FAILED_PKG=$(grep -oE "package/.* failed" "$BUILD_LOG" | head -1 | awk '{print $1}')
    if [[ -n "$FAILED_PKG" ]]; then
        echo -e "${LYELLOW}Detected failed package: ${FAILED_PKG}${NC}"
        echo -e "${LYELLOW}Attempting build without problematic packages...${NC}"
        
        # Удаляем проблемный пакет и пробуем снова
        FILTERED_PACKAGES=$(echo "$CUSTOM_PACKAGES" | sed "s/$FAILED_PKG//g")
        
        make V=s -j1 image PROFILE="$IMAGE_PROFILE" \
            PACKAGES="$FILTERED_PACKAGES" \
            FILES="$WORK_DIR" \
            BIN_DIR="$OUTPUT_DIR" \
            ${KERNEL_SIZE:+CONFIG_TARGET_KERNEL_PARTSIZE=$KERNEL_SIZE} \
            ${ROOT_SIZE:+CONFIG_TARGET_ROOTFS_PARTSIZE=$ROOT_SIZE} 2>&1 | tee -a "$BUILD_LOG"
    else
        echo -e "${LRED}Could not identify specific failed package. Full log below:${NC}"
        cat "$BUILD_LOG"
        exit 1
    fi
}

# VM conversion if requested
if $CREATE_VM; then
    echo -e "${GREEN}Creating VMware image...${NC}"
    for img in "$OUTPUT_DIR"/*.img; do
        if [[ -f "$img" ]]; then
            qemu-img convert -f raw -O vmdk "$img" "${img%.*}.vmdk"
        fi
    done
fi

echo -e "${GREEN}=== Build Complete ==="
echo -e "Output files in: ${LYELLOW}${OUTPUT_DIR}${NC}"
ls -lh "$OUTPUT_DIR"
