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

For a serial console on `com0` at 115200 baud, build the image with
`SERIAL_CONSOLE=com0`:

    make SERIAL_CONSOLE=com0 install80.img

Set your terminal to 115200, 8 data bits, no parity, and 1 stop bit. The
installer will use the serial console, and HAMMER2 installs made from that
image will retain the same setting. Re-run the build command to change the
console setting on an existing image.

On an existing HAMMER2 installation, put these lines in
`/bootfs/etc/boot.conf` (keep any other boot commands you need):

    stty com0 115200
    set tty com0
    boot /bsd.hammer2

If the boot filesystem is mounted elsewhere, use its `etc/boot.conf` instead.
The serial console switch takes effect on the next boot. A serial BREAK then
enters `ddb` when `ddb.console=1`.

## Install on a machine

Write `install80.img` to a USB drive. Replace `sdX` with the USB drive's device name. This erases the drive.

    doas dd if=install80.img of=/dev/rsdXc bs=1m

Boot the machine from the USB drive and choose `I` for Install. Select the target disk, then choose HAMMER2 when asked for the root filesystem. The installer can put HAMMER2 and the FFS boot partition on one disk, or put HAMMER2 on a second disk. For a same-disk install, enter the swap size in MiB (128 by default); enter 0 to disable swap and give the remaining space to HAMMER2.

Choose the USB drive as the set source for a HAMMER2 install. Its `h2relink80.tgz` set is selected by default and supplies the matching objects for boot-time kernel relinking. The installed system verifies and relinks `/bootfs/bsd.hammer2` at boot; logs are in `/usr/share/relink/kernel/amd64.MP/relink.log` with the default kernel build directory.
After rebuilding or updating the HAMMER2 kernel, install a link kit from the same build before boot-time relinking can use the new kernel.
