# OpenBSD HAMMER2

**Warning:** This is experimental code and is not intended for normal use. Do not use it for data you need to keep.

## Build and install

Build on OpenBSD 8.0 amd64. From this repository, run:

    make fetch-src
    make prep
    make kernel
    make install

`make fetch-src` installs the OpenBSD source tree in `/usr/src`. It stops if that directory already contains files. `make prep` applies this project's OpenBSD patch and links the HAMMER2 sources into the tree.

## Build the install image

To build an image with a HAMMER2 root option, run:

    make install80.img

The result is `install80.img` in this directory. The build downloads the official OpenBSD 8.0 install image unless you provide one:

    make INSTALL80_BASE=/path/to/original/install80.img install80.img

## Install on a machine

Write `install80.img` to a USB drive. Replace `sdX` with the USB drive's device name. This erases the drive.

    doas dd if=install80.img of=/dev/rsdXc bs=1m

Boot the machine from the USB drive and choose `I` for Install. Select the target disk, then choose HAMMER2 when asked for the root filesystem. The installer can put HAMMER2 and the FFS boot partition on one disk, or put HAMMER2 on a second disk. For a same-disk install, enter the swap size in MiB (128 by default); enter 0 to disable swap and give the remaining space to HAMMER2.
