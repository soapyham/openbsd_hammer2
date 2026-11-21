#!/bin/sh
# Build an OpenBSD 8.0 amd64 installer image with the HAMMER2 payload.
set -eu

usage() {
	echo "usage: $0 output.img [base-install80.img] [hammer2-kernel] [ramdisk-kernel]" >&2
	exit 1
}

[ "$#" -ge 1 ] && [ "$#" -le 4 ] || usage
[ "$(id -u)" -eq 0 ] || { echo 'image assembly requires root' >&2; exit 1; }

output=$1
base=${2:-}
kernel=${3:-.obj/kernel/amd64.MP/bsd}
ramdisk_kernel=${4:-.obj/kernel/amd64.RAMDISK.HAMMER2/bsd}
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$output" in /*) ;; *) output="$(pwd)/$output" ;; esac
case "$kernel" in /*) ;; *) kernel="$(pwd)/$kernel" ;; esac
case "$ramdisk_kernel" in /*) ;; *) ramdisk_kernel="$(pwd)/$ramdisk_kernel" ;; esac
[ -f "$kernel" ] || { echo "missing kernel: $kernel" >&2; exit 1; }
[ -f "$ramdisk_kernel" ] || {
	echo "missing ramdisk kernel: $ramdisk_kernel" >&2; exit 1;
}
[ -f /usr/src/sbin/disklabel/Makefile ] &&
    grep -q FS_HAMMER2 /usr/src/sys/sys/disklabel.h || {
	echo 'patched OpenBSD disklabel sources are required; run make prep' >&2; exit 1;
}
for tool in hammer2 newfs_hammer2 mount_hammer2 fsck_hammer2; do
	[ -x "$repo/src/sbin/$tool/$tool" ] || {
		echo "missing $tool; run make first" >&2; exit 1;
	}
done

work=$(mktemp -d /tmp/hammer2-install80.XXXXXXXX)
srcvnd=
dstvnd=
rdvnd=
srcmounted=no
dstmounted=no
rdmounted=no
cleanup() {
	if [ "$rdmounted" = yes ]; then umount "$work/stock-mr" || :; fi
	if [ "$dstmounted" = yes ]; then umount "$work/dst" || :; fi
	if [ "$srcmounted" = yes ]; then umount "$work/src" || :; fi
	if [ -n "$rdvnd" ]; then vnconfig -u "$rdvnd" || :; fi
	if [ -n "$dstvnd" ]; then vnconfig -u "$dstvnd" || :; fi
	if [ -n "$srcvnd" ]; then vnconfig -u "$srcvnd" || :; fi
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM
mkdir "$work/src" "$work/dst"

if [ -z "$base" ]; then
	base="$work/install80.img"
	url=https://cdn.openbsd.org/pub/OpenBSD/8.0/amd64
	ftp -o "$base" "$url/install80.img"
	ftp -o "$work/SHA256.sig" "$url/SHA256.sig"
	(cd "$work" && signify -C -q -p /etc/signify/openbsd-80-base.pub \
	    -x SHA256.sig install80.img)
fi
[ -f "$base" ] || { echo "missing base image: $base" >&2; exit 1; }
case "$base" in /*) ;; *) base="$(pwd)/$base" ;; esac
[ "$base" != "$output" ] || { echo 'base and output must differ' >&2; exit 1; }

# The release image is full. Recreate its partition layout with 128 MiB more
# space, preserving the signed release sets and the original EFI filesystem.
size=$(stat -f %z "$base")
[ "$size" -gt 800000000 ] || { echo 'base image is unexpectedly small' >&2; exit 1; }
total=$((size / 512 + 128 * 2048))
fssize=$((total - 960))
dd if=/dev/zero of="$work/output.img" bs=512 count=1 seek=$((total - 1))
srcvnd=$(vnconfig -v "$base" | tail -1)
dstvnd=$(vnconfig -v "$work/output.img" | tail -1)
fdisk -yi -l "$fssize" -b 960 -f /usr/mdec/mbr "$dstvnd"
echo '/ *' | disklabel -wAT- "$dstvnd"
dd if="/dev/r${srcvnd}i" of="/dev/r${dstvnd}i" bs=64k
newfs -O 1 -m 0 -o space -i 524288 -c "$fssize" "/dev/r${dstvnd}a"
mount -r "/dev/${srcvnd}a" "$work/src"
srcmounted=yes
[ -f "$work/src/8.0/amd64/bsd.rd" ] && [ -f "$work/src/boot" ] || {
	echo 'base image is not an OpenBSD 8.0 amd64 installer' >&2; exit 1;
}
mount "/dev/${dstvnd}a" "$work/dst"
dstmounted=yes
(cd "$work/src" && pax -rw -pe . "$work/dst")

payload="$work/dst/8.0/amd64"
mkdir -p "$payload/hammer2-tools"

# Expand the release installer ramdisk and add HAMMER2 support without
# rebuilding OpenBSD's crunched installer binary.
gzip -dc "$work/src/8.0/amd64/bsd.rd" > "$work/stock-bsd.rd"
rdsetroot -x "$work/stock-bsd.rd" "$work/stock-mr.fs"
mkdir "$work/stock-mr" "$work/custom-mr"
rdvnd=$(vnconfig -v "$work/stock-mr.fs" | tail -1)
mount -r "/dev/${rdvnd}a" "$work/stock-mr"
rdmounted=yes
(cd "$work/stock-mr" && pax -rw -pe . "$work/custom-mr")
python3 "$repo/script/enable-hammer2-install.py" "$work/custom-mr/install.sub"
gzip -9cn "$kernel" > "$work/custom-mr/bsd.hammer2.gz"
cp "$work/src/boot" "$work/custom-mr/boot"
umount "$work/stock-mr"
rdmounted=no
vnconfig -u "$rdvnd"
rdvnd=

install -m 555 "$kernel" "$work/dst/bsd.hammer2"
install -m 555 "$kernel" "$payload/bsd.hammer2"
for tool in hammer2 newfs_hammer2 mount_hammer2 fsck_hammer2; do
	install -m 555 "$repo/src/sbin/$tool/$tool" "$payload/hammer2-tools/$tool"
done

# Boot the full HAMMER2 kernel against the install image's FFS partition.
# A small single-user root gives it a shell and the tools needed to prepare
# another disk. The stock ramdisk installer remains selectable as bsd.rd.
mkdir -p "$work/dst/bin" "$work/dst/sbin" "$work/dst/dev" \
    "$work/dst/usr/lib" "$work/dst/usr/libexec" "$work/dst/tmp"
chmod 1777 "$work/dst/tmp"
for binary in /bin/ksh /bin/ls /bin/mkdir /bin/cp /bin/pax \
    /sbin/init /sbin/fdisk /sbin/mount /sbin/umount \
    /sbin/reboot /sbin/newfs /sbin/mount_ffs /sbin/fsck_ffs; do
	install -m 555 "$binary" "$work/dst$binary"
done
ln -s ksh "$work/dst/bin/sh"
mkdir "$work/disklabel"
cp /usr/src/sbin/disklabel/Makefile /usr/src/sbin/disklabel/*.[ch] \
    "$work/disklabel/"
make -s -C "$work/disklabel" NOMAN=1 CFLAGS=-I/usr/src/sys
install -m 555 "$work/disklabel/disklabel" "$work/dst/sbin/disklabel"
install -m 555 "$work/disklabel/disklabel" "$payload/hammer2-tools/disklabel"
rm "$work/custom-mr/sbin/disklabel"
install -m 555 "$work/disklabel/disklabel" "$work/custom-mr/sbin/disklabel"
for binary in "$work/disklabel/disklabel" \
    "$repo/src/sbin/hammer2/hammer2" \
    "$repo/src/sbin/newfs_hammer2/newfs_hammer2" \
    "$repo/src/sbin/mount_hammer2/mount_hammer2" \
    "$repo/src/sbin/fsck_hammer2/fsck_hammer2"; do
	install -m 555 "$binary" "$work/dst/sbin/$(basename "$binary")"
	if [ "$binary" != "$work/disklabel/disklabel" ]; then
		install -m 555 "$binary" "$work/custom-mr/sbin/$(basename "$binary")"
	fi
	ldd "$binary" | awk '$NF ~ /^\/usr\// { print $NF }' |
	while IFS= read -r library; do
		[ -f "$work/dst$library" ] || install -m 444 "$library" "$work/dst$library"
		mkdir -p "$work/custom-mr$(dirname "$library")"
		[ -f "$work/custom-mr$library" ] ||
		    install -m 444 "$library" "$work/custom-mr$library"
	done
done

makefs -s 40m -o rdroot,minfree=0,density=4096,bsize=4096,fsize=512 \
    "$work/custom-mr.fs" "$work/custom-mr"
# makefs's generic rdroot label omits geometry needed by vnd; write a
# complete label so the image is mountable for inspection and by rd(4).
cat > "$work/ramdisk.label" <<'EOF'
type: vnd
disk: rdroot
label: HAMMER2 ramdisk
bytes/sector: 512
sectors/track: 100
tracks/cylinder: 1
sectors/cylinder: 100
cylinders: 820
total sectors: 81920
boundstart: 0
boundend: 49152
16 partitions:
  a: 81920 0 4.2BSD 512 4096 0
EOF
rdvnd=$(vnconfig -v "$work/custom-mr.fs" | tail -1)
disklabel -R "$rdvnd" "$work/ramdisk.label"
vnconfig -u "$rdvnd"
rdvnd=
[ "$(stat -f %z "$work/custom-mr.fs")" -eq "$(rdsetroot -s "$ramdisk_kernel")" ] || {
	echo 'custom ramdisk size differs from kernel reservation' >&2; exit 1;
}
cp "$ramdisk_kernel" "$work/bsd.rd"
rdsetroot "$work/bsd.rd" "$work/custom-mr.fs"
objcopy -g -x -R .comment -R .SUNW_ctf -K rd_root_size -K rd_root_image \
    "$work/bsd.rd" "$work/bsd.strip"
gzip -9cn "$work/bsd.strip" > "$work/bsd.rd.gz"
rm "$work/dst/bsd" "$work/dst/bsd.rd"
install -m 555 "$work/bsd.rd.gz" "$work/dst/bsd.rd"
ln "$work/dst/bsd.rd" "$work/dst/bsd"
install -m 555 "$work/bsd.rd.gz" "$payload/bsd.rd.hammer2"
cp /dev/MAKEDEV "$work/dst/dev/MAKEDEV"
(cd "$work/dst/dev" && sh ./MAKEDEV std sd0 sd1 sd2)
cp /etc/ttys "$work/dst/etc/ttys"
cat > "$work/dst/etc/boot.conf" <<'EOF'
set image /bsd.rd
EOF
cat > "$payload/hammer2-tools/README" <<'EOF'
HAMMER2 tools for OpenBSD 8.0 amd64

The image boots its custom HAMMER2-enabled bsd.rd installer by default.
Choose (S)hell to use disklabel and the HAMMER2 tools in the ramdisk.
Create target device nodes with "cd /dev && sh MAKEDEV sd1" as needed.
The full /bsd.hammer2 kernel remains available with "boot /bsd.hammer2 -s"
at the boot prompt.
At the shell, use disklabel to assign HAMMER2 to the intended partition,
then run newfs_hammer2 on its raw device. The four HAMMER2 utilities are in
/sbin and also in 8.0/amd64/hammer2-tools. The same kernel is copied to
8.0/amd64/bsd.hammer2 for installation on an FFS boot partition.
The ramdisk root is writable; mount points can be created under /mnt.
When using the full kernel single-user shell, remount the image writable
with "mount -u -o rw /dev/sd0a /" (adjust the device if needed).

The unmodified release installer remains at /8.0/amd64/bsd.rd, and the
custom installer is also at /8.0/amd64/bsd.rd.hammer2. The stock ramdisk
cannot mount HAMMER2. The (I)nstall workflow offers HAMMER2 root on the same
disk or a second disk. For one disk of at least 4 GiB, choose "same disk".
The installer creates a 512 MiB FFS boot partition a, 128 MiB swap partition
b, and HAMMER2 partition d. HAMMER2 uses the full partition size, rounded
down to its required alignment. For EFI boot, choose whole disk GPT or an
OpenBSD GPT area with an EFI System Partition. The installer copies the EFI
loaders to that partition during installboot. The HAMMER2 kernel selects the
root partition automatically when it is unambiguous. If multiple HAMMER2
partitions make the choice ambiguous, enter the root and swap devices at
the prompts. For two disks, choose
"second disk"; the FFS boot disk is initialized normally, and HAMMER2 uses
partition a of a separate disk of at least 4 GiB.
See HAMMER2_ROOT_BOOT_PLAN.md in the source repository for the tested VM path.
EOF

installboot -v -r "$work/dst" "$dstvnd" /usr/mdec/biosboot "$work/dst/boot"
sync
umount "$work/dst"
dstmounted=no
umount "$work/src"
srcmounted=no
vnconfig -u "$dstvnd"
dstvnd=
vnconfig -u "$srcvnd"
srcvnd=
mv "$work/output.img" "$output"
echo "Created $output"
