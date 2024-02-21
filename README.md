# OpenWRT x86 custom image build, partition resize & virtual machine conversion script

### **This project simplifies building custom OpenWRT images, enables the enlargement of default partitions to support a larger number of packages, and optionally converts new OpenWRT builds into virutal machine images.**

**The x86-imagebuilder.sh script presents the following OpenWRT build option prompts:**

- **1. Enter a specifc OWRT release version** - [or hit enter for lastest snapshot]
- **2. Modify partition sizes or keep OpenWRT defaults? [y/n]** - [y prompts for custom kernel & root partition values]
- **3. Add an image filename tag?** - [enter a unique filename tag to idenfity this build]
- **4. Convert completed OpenWRT builds to VMware VMDK? [y/n]**
- **5. Include custom config files in the new image?** - [Prompt to copy config files before beginning build]


## Prerequisites
Any recent Debian flavoured OS should work fine. (Curl and build-essentials dependencies are automatically installed). 

## Instructions

1. Download the imagebuilder script and make it executable: `chmod +x x86-imagebuilder.sh`

2. Customize the list of packages to include in your new image under the CUSTOM_PACKAGES section. Below is an example:
   ```
   CUSTOM_PACKAGES="blockd block-mount curl dnsmasq dnsmasq-full kmod-fs-ext4 kmod-usb2 kmod-usb3 kmod-usb-storage kmod-usb-core \
   usbutils nano socat tcpdump luci luci-app-ddns luci-app-mwan3 mwan3 luci-app-openvpn openvpn-openssl luci-app-samba4 open-vm-tools"
   ```
3. Run the script as sudo and follow the prompts: `sudo ./x86-imagebuilder.sh`

4. If baking custom settings into new images, when prompted copy your custom OWRT config files to `$(pwd)/openwrt_inject_files` and hit enter to start the build. 

5. Choose your completed firmware variant for flashing under `$(pwd)/firmware_images`, or the converted VMDK version from `$(pwd)/vmdk`


## Further filesystem expansion beyond resized partitions.

It is also possible to combine SquashFS with a third _**and pesistent**_ EXT4 data partition. After image installation, simply add a new EXT4 partition and update its PART-UUID details in the OpenWRT fstab file. Next, take a copy of the updated fstab file and inject this into a 2nd new OpenWRT image build. Now the fstab and new EXT4 partition is permanently built into the image and won't be affected by future sysupgrades.

**Note: While it is possible to adapt this script for other architecture targets, partition resize and VMDK conversion options should only be used with x86 builds. Do not resize default partition sizes with firmware images intended for router flash storage unless you absolutely know what you are doing and how to recover your device from a bricked state.**


