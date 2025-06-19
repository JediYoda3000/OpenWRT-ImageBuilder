#!/bin/bash
#######################################################################################################################
# Build and virtualize custom OpenWRT images for x86 with UEFI and Btrfs support
# Modified for UEFI and Btrfs support
#######################################################################################################################

clear

# Prepare text output colours
LYELLOW='\033[0;93m'
LRED='\033[0;91m'
NC='\033[0m' #No Colour

if ! [[ $(id -u) = 0 ]]; then
    echo
    echo -e "${LRED}Please run this script as sudo.${NC}" 1>&2
    echo
    exit 1
fi

echo -e "${LYELLOW}Checking for wget...${NC}"
apt-get update -qq
apt-get install wget sudo -qq -y

clear

#######################################################################################################################
# User input variables
#######################################################################################################################

# Default version to 24.10.1 but allow override
VERSION="24.10.1"            # Default to 24.10.1 but can be changed
TARGET="x86"                 # x86, mvebu etc
ARCH="64"                    # 64, cortexa9 etc
IMAGE_PROFILE="generic"      # x86 = generic, linksys_wrt1900acs etc
RELEASE_URL="https://downloads.openwrt.org/releases/"

# Updated default packages with UEFI and Btrfs support
CUSTOM_PACKAGES="blockd block-mount kmod-fs-btrfs btrfs-progs kmod-fs-ext4 kmod-usb2 kmod-usb3 kmod-usb-storage kmod-usb-core usbutils \
-dnsmasq dnsmasq-full luci luci-app-pbr \
luci-app-ksmbd luci-app-sqm sqm-scripts sqm-scripts-extra luci-app-attendedsysupgrade auc \
curl nano socat tcpdump python3-light python3-netifaces wsdd2 igmpproxy iptables-mod-ipopt \
usbmuxd libimobiledevice kmod-usb-net kmod-usb-net-asix-ax88179 kmod-mt7921u kmod-usb-net-rndis kmod-usb-net-ipheth \
byobu zsh blkid tmux screen cfdisk resize2fs git git-http htop losetup luci-app-dockerman luci-app-ttyd luci-i18n-base-ru luci-proto-wireguard luci-app-wireguard vim"

# Initialise prompt variables
MOD_PARTSIZE=""              # true/false
KERNEL_PARTSIZE=""           # variable set in MB
ROOT_PARTSIZE=""             # variable set in MB (values over 8192 may give memory exhaustion errors)
KERNEL_RESIZE_DEF="32"       # Default increased partition size in MB
ROOT_RESIZE_DEF="512"        # Default increased partition size in MB
IMAGE_TAG=""                 # This ID tag will be added to the completed image filename
CREATE_VM=""                 # Create VMware images of the final build true/false
BUILD_LOG="$(pwd)/build.log"
UEFI_ENABLE=""               # Enable UEFI support
BTRFS_ENABLE=""              # Enable Btrfs root filesystem

# Set LAN config
MOD_LAN=""                   # true/false
LAN_PROTO=""                 # static/dhcp
LAN_IP=""                    # ip wan
LAN_GATEWAY=""               # gateway
LAN_DNS=""                   # dns
LAN_SSH_ACCESS=""            # open ssh port true/false

#######################################################################################################################
# Script user prompts
#######################################################################################################################

echo -e ${LYELLOW}
echo "Image Builder activity will be logged to ${BUILD_LOG}"
echo

# Prompt for the desired OWRT version
if [[ -z ${VERSION} ]]; then
    LATEST_RELEASE=$(wget -qO- "$RELEASE_URL" | grep -oP "([0-9]+\.[0-9]+\.[0-9]+)" | sort -V | tail -n1)
    echo
    echo -e "${LYELLOW}Enter OpenWRT version to build: ${NC}"
    while true; do
        read -p "    Enter a version number (latest stable release is $LATEST_RELEASE), or leave blank for latest snapshot: " VERSION
        [[ "${VERSION}" = "" ]] || [[ "${VERSION}" != "" ]] && break
    done
    echo
else
    echo -e "${LYELLOW}Using OpenWRT version: ${VERSION}${NC}"
fi

# Prompt for UEFI support
if [[ -z ${UEFI_ENABLE} ]]; then
    echo -e "${LYELLOW}UEFI Support:${NC}"
    echo -e -n "    Enable UEFI support? [Y/n]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Nn]$ ]]; then
        UEFI_ENABLE=false
    else
        UEFI_ENABLE=true
    fi
fi

# Prompt for Btrfs support
if [[ -z ${BTRFS_ENABLE} ]]; then
    echo -e "${LYELLOW}Filesystem Type:${NC}"
    echo -e -n "    Use Btrfs as root filesystem? [Y/n]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Nn]$ ]]; then
        BTRFS_ENABLE=false
    else
        BTRFS_ENABLE=true
        # Add Btrfs packages if selected
        CUSTOM_PACKAGES+=" kmod-fs-btrfs btrfs-progs"
    fi
fi

# Prompt to resize image partitions
if [[ -z ${MOD_PARTSIZE} ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then
    echo -e "${LYELLOW}Modify OpenWRT Partitions (x86 ONLY):${NC}"
    echo -e -n "    Modify partition sizes? [ n = no changes (default) | y = resize ] [y/N]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        MOD_PARTSIZE=true
    else
        MOD_PARTSIZE=false
    fi
fi

# Set custom partition sizes
if [[ ${MOD_PARTSIZE} = true ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then
    [[ -z ${KERNEL_PARTSIZE} ]] &&
        read -p "    x86 ONLY!: Enter KERNEL partition size in MB [Hit enter for ${KERNEL_RESIZE_DEF}, or enter custom size]: " KERNEL_PARTSIZE
    [[ -z ${ROOT_PARTSIZE} ]] &&
        read -p "    x86 ONLY!: Enter ROOT partition size in MB [Hit enter for ${ROOT_RESIZE_DEF}, or enter custom size]: " ROOT_PARTSIZE
fi

# If no kernel partition size value given, create a default value
if [[ ${MOD_PARTSIZE} = true ]] && [[ -z ${KERNEL_PARTSIZE} ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then
    KERNEL_PARTSIZE=$KERNEL_RESIZE_DEF
fi

# If no root partition size value given, create a default value
if [[ ${MOD_PARTSIZE} = true ]] && [[ -z ${ROOT_PARTSIZE} ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then
    ROOT_PARTSIZE=$ROOT_RESIZE_DEF
fi

# Create a custom image name tag
if [[ -z ${IMAGE_TAG} ]]; then
    echo
    echo -e "${LYELLOW}Custom image filename identifier:${NC}"
    while true; do
        read -p "    Enter text to include in the image filename [Enter for \"custom\"]: " IMAGE_TAG
        [[ "${IMAGE_TAG}" = "" ]] || [[ "${IMAGE_TAG}" != "" ]] && break
    done
fi

# If no image name tag is given, create a default value
if [[ -z ${IMAGE_TAG} ]]; then
    IMAGE_TAG="custom"
fi

# Convert images for use in virtual environment?"
if [[ -z ${CREATE_VM} ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then
    echo
    echo -e "${LYELLOW}Virtual machine image conversion:${NC}"
    echo -e -n "    x86 ONLY!: Convert new OpenWRT images to virtual machines? (VMware) [default = n] [y/N]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        CREATE_VM=true
    else
        CREATE_VM=false
    fi
fi

# Set Lan config?"
if [[ -z ${MOD_LAN} ]]; then
    echo
    echo -e "${LYELLOW}Configuring the LAN interface:${NC}"
    read -p "    Change LAN config [y/N]: " PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        MOD_LAN=true
    else
        MOD_LAN=false
    fi

    if [[ ${MOD_LAN} = true ]]; then
        read -p "    Set LAN config DHCP [Y/n]: " PROMPT
        if [[ ${PROMPT} =~ ^[Nn]$ ]]; then
            LAN_PROTO="static"
            PROMPT=false;
        else
            LAN_PROTO="dhcp"
            PROMPT=true;
        fi
    fi
    if [[ ${MOD_LAN} = true ]] && [[ ${PROMPT} = false ]]; then
        read -p "    Set IP: " LAN_IP
        read -p "    Set Gateway: " LAN_GATEWAY
        read -p "    Set DNS: " LAN_DNS
    fi
fi

#######################################################################################################################
# Setup the image builder working environment
#######################################################################################################################

# Create the the OpenWRT download link
if [[ ${VERSION} != "" ]]; then
    BUILDER="https://downloads.openwrt.org/releases/${VERSION}/targets/${TARGET}/${ARCH}/openwrt-imagebuilder-${VERSION}-${TARGET}-${ARCH}.Linux-x86_64.tar.xz"
else
    BUILDER="https://downloads.openwrt.org/snapshots/targets/${TARGET}/${ARCH}/openwrt-imagebuilder-${TARGET}-${ARCH}.Linux-x86_64.tar.xz" # Current snapshot
fi

# Configure the build paths
SOURCE_FILE="${BUILDER##*/}" # Separate the tar.xz file name from the source download link
SOURCE_DIR="${SOURCE_FILE%%.tar.xz}" # Get the uncompressed tar.xz directory name and set as the source dir
BUILD_ROOT="$(pwd)/openwrt_build_output"
OUTPUT="${BUILD_ROOT}/firmware_images"
VMDIR="${BUILD_ROOT}/vm"
INJECT_FILES="$(pwd)/openwrt_inject_files"

#######################################################################################################################
# Begin script build actions
#######################################################################################################################

# Clear out any previous builds
rm -rf "${BUILD_ROOT}"
rm -rf "${SOURCE_DIR}"

# Create the destination directories
mkdir -p "${BUILD_ROOT}"
mkdir -p "${OUTPUT}"
mkdir -p "${INJECT_FILES}"
if [[ ${CREATE_VM} = true ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then mkdir -p "${VMDIR}" ; fi
chown -R $SUDO_USER $INJECT_FILES
chown -R $SUDO_USER $BUILD_ROOT

if [[ ${MOD_LAN} = true ]]; then
    mkdir -p "${INJECT_FILES}/etc/uci-defaults/"
    echo "uci -q batch << EOI
set network.lan.proto='${LAN_PROTO}'
set network.lan.ipaddr='${LAN_IP}'
set network.lan.gateway='${LAN_GATEWAY}'
set network.lan.dns='${LAN_DNS}'
commit
EOI
" > ${INJECT_FILES}/etc/uci-defaults/99-wan-set-defaults
fi

# Option to pre-configure images with injected config files
echo -e ${LYELLOW}
read -p $"Copy optional config files to ${INJECT_FILES} now for inclusion into the new image. Enter to begin build..."
echo -e ${NC}

# Install OWRT build system dependencies with additional packages for UEFI and Btrfs
sudo apt-get update  2>&1 | tee -a ${BUILD_LOG}
sudo apt-get install -y build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
gettext git libncurses-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget qemu-utils \
dosfstools mtools uuid-runtime parted 2>&1 | tee -a ${BUILD_LOG}

# Download the image builder source if we haven't already
if [ ! -f "${BUILDER##*/}" ]; then
    wget -q --show-progress "$BUILDER"
    tar xJvf "${BUILDER##*/}" --checkpoint=.100 2>&1 | tee -a ${BUILD_LOG}
fi

# Uncompress if the source tar.xz exists but there is no uncompressed source directory
if [ -n "${SOURCE_DIR}" ]; then
    tar xJvf "${BUILDER##*/}" --checkpoint=.100 2>&1 | tee -a ${BUILD_LOG}
fi

# Remove sudo access limits on source download
chown -R $SUDO_USER:root $SOURCE_FILE
chown -R $SUDO_USER:root $SOURCE_DIR

# Configure UEFI and Btrfs settings in the image builder
if [[ ${UEFI_ENABLE} = true ]]; then
    echo -e "${LYELLOW}Configuring UEFI support...${NC}"
    # Patch the source config for UEFI support
    sed -i '/CONFIG_GRUB_IMAGES/d' "$PWD/$SOURCE_DIR/.config"
    sed -i '/CONFIG_EFI_IMAGES/d' "$PWD/$SOURCE_DIR/.config"
    echo "CONFIG_EFI_IMAGES=y" >> "$PWD/$SOURCE_DIR/.config"
    echo "CONFIG_GRUB_IMAGES=y" >> "$PWD/$SOURCE_DIR/.config"
    echo "CONFIG_GRUB_EFI_IMAGES=y" >> "$PWD/$SOURCE_DIR/.config"
    echo "CONFIG_GRUB_TIMEOUT=\"3\"" >> "$PWD/$SOURCE_DIR/.config"
fi

if [[ ${BTRFS_ENABLE} = true ]]; then
    echo -e "${LYELLOW}Configuring Btrfs support...${NC}"
    # Patch the source config for Btrfs support
    sed -i '/CONFIG_TARGET_ROOTFS_BTRFS/d' "$PWD/$SOURCE_DIR/.config"
    echo "CONFIG_TARGET_ROOTFS_BTRFS=y" >> "$PWD/$SOURCE_DIR/.config"
    echo "CONFIG_PACKAGE_btrfs-progs=y" >> "$PWD/$SOURCE_DIR/.config"
fi

# Reconfigure the partition sizing source files (for x86 build only)
if [[ ${MOD_PARTSIZE} = true ]] && [[ ${IMAGE_PROFILE} = "generic" ]]; then
    # Patch the source partition size config settings
    sed -i "s/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=$KERNEL_PARTSIZE/g" "$PWD/$SOURCE_DIR/.config"
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=$ROOT_PARTSIZE/g" "$PWD/$SOURCE_DIR/.config"
    # Patch for source partition size config settings giving errors
    sed -i '/\$(CONFIG_TARGET_ROOTFS_PARTSIZE) \$(IMAGE_ROOTFS)/,/256/ s/256/'"$ROOT_PARTSIZE"'/' "$PWD/$SOURCE_DIR/target/linux/x86/image/Makefile"
fi

# Start a clean image build with the selected packages
cd $(pwd)/"${SOURCE_DIR}"/
make clean 2>&1 | tee -a ${BUILD_LOG}
make image PROFILE="${IMAGE_PROFILE}" PACKAGES="${CUSTOM_PACKAGES}" EXTRA_IMAGE_NAME="${IMAGE_TAG}" FILES="${INJECT_FILES}" BIN_DIR="${OUTPUT}" 2>&1 | tee -a ${BUILD_LOG}

if [[ ${CREATE_VM} = true ]]; then
    # Copy the new images to a separate directory for conversion to vm image
    cp $OUTPUT/*.gz $VMDIR
    # Create a list of new images to unzip
    for LIST in $VMDIR/*img.gz
    do
        echo $LIST
        gunzip $LIST
    done
    # Convert the unzipped images
    for LIST in $VMDIR/*.img
    do
        echo $LIST
        qemu-img convert -f raw -O vmdk $LIST $LIST.vmdk 2>&1 | tee -a ${BUILD_LOG}
    done
    # Clean up
    rm -f $VMDIR/*.img
fi

echo -e "${LYELLOW}Build complete!${NC}"
echo -e "Output files are located in: ${OUTPUT}"
if [[ ${UEFI_ENABLE} = true ]]; then
    echo -e "UEFI-enabled images have been created"
fi
if [[ ${BTRFS_ENABLE} = true ]]; then
    echo -e "Btrfs root filesystem has been configured"
fi
