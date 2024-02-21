# Custom OpenWRT x86 image build & VM conversion script

### This project supports a flexible approach to creating custom firmware recipes through:
  - A custom packages manifest
  - Optional resize of default partitions to unlock extra filesystem storage
  - Optional conversion of new OpenWRT builds into VMware vmdk images. (edit script for qcow2, qed, vdi or vhd)

**Script option prompts:**

  1. Enter a specifc OpenWRT stable release version _[ or hit enter for lastest snapshot ]_
  2. Modify partition sizes or keep OpenWRT defaults? [y/n] _[ n skips, y prompts further for new kernel & root partition sizes ]_
  4. enter new image filename tag  _[ enter a name tag to include within the new image filename ]_
  5. Convert completed OpenWRT builds to VMware VMDK? [y/n] 
  6. Bake custom OpenWRT config files into the new image? _[ A final prompt to copy custom config files before beginning build ]_

## Prerequisites
Any recent x86 Debian flavoured x86 OS should work fine. Curl and all build-essentials dependencies are automatically installed.

## Instructions

1. Download the imagebuilder script and make it executable: `chmod +x x86-imagebuilder.sh`

2. Customize the list of packages to include in your new image under the CUSTOM_PACKAGES section of the script. (Packages shown in the script are just an example and these can be changed to anyting you like).

3. Run the script as sudo and follow the prompts: `sudo ./x86-imagebuilder.sh`

4. If baking custom settings into new images, when prompted copy your custom OpenWRT config files to `$(pwd)/openwrt_inject_files` and hit enter to start the build. 

5. Choose your completed firmware variant for flashing under `$(pwd)/firmware_images`, or the converted virutal machine image from `$(pwd)/vm`


## Persistent filesystem expansion without resized partitions

It is possible to combine default SquashFS with a third _**pesistent**_ EXT4 data partition that won't be wiped by future sysupgrades.
1. After image installation, simply create a new EXT4 partition and add its PART-UUID details into the OpenWRT fstab file.
2. Next, re-run the script and add the new fstab file along with any other custom files to the $(pwd)/openwrt_inject_files when prompted.
3. Reflash your system with the new updated fstab build. Now the fstab and new EXT4 partition location and config is permanently baked into the image.

- **Note 1: It is possible to change this script to build for any OpenWRT target, just remember that partition resize and VM conversion options should only be used with x86 builds. Do not attempt to resize partitions of firmware images intended for specific router models with NAND flash memory.**
- **Note 2: Inages with modified default partition sizes may have issues with online attended sysupgrades. You must rebuild your own updates images and re-flash manually.**


