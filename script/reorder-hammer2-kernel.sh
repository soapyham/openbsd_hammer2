#!/bin/ksh
# Relink the HAMMER2 kernel installed on the FFS boot partition.
set -o errexit
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

KERNEL=$(sysctl -n kern.osversion)
KERNEL=${KERNEL%#*}
read -r EXPECTED_KERNEL </etc/hammer2-relink-kernel
KERNEL_DIR=/usr/share/relink/kernel/$KERNEL
BOOT_KERNEL=/bootfs/bsd.hammer2
SHA256=/var/db/kernel.hammer2.SHA256
LOGFILE=$KERNEL_DIR/relink.log
PROGNAME=${0##*/}

df -t nonfs /usr/share/relink/kernel >/dev/null 2>&1
ERRMSG='failed'
trap 'trap - EXIT; logger -st $PROGNAME "$ERRMSG" >/dev/console 2>&1' ERR
trap 'logger -t $PROGNAME "kernel relinking done"' EXIT

mkdir -m 700 -p "$KERNEL_DIR"
exec 1>"$LOGFILE"
exec 2>&1
ERRMSG="failed -- see $LOGFILE"

[[ $KERNEL == $EXPECTED_KERNEL ]] || {
	echo "Link kit $EXPECTED_KERNEL does not match running kernel $KERNEL"
	false
}
[[ -f $KERNEL_DIR/Makefile ]] || { echo "Missing HAMMER2 link kit: $KERNEL_DIR"; false; }
sha256 -C "$SHA256" "$BOOT_KERNEL" || {
	echo "HAMMER2 kernel checksum mismatch: $BOOT_KERNEL"
	false
}

cd "$KERNEL_DIR"
make newbsd
make reconfig
make newinstall
sync
echo "HAMMER2 kernel relinked for next boot."
