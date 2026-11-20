#!/bin/sh
# Build an OpenBSD 8.0 amd64 installer image with the HAMMER2 payload.
set -eu

usage() {
	echo "usage: $0 output.img [base-install80.img] [hammer2-kernel]" >&2
	exit 1
}

[ "$#" -ge 1 ] && [ "$#" -le 3 ] || usage
[ "$(id -u)" -eq 0 ] || { echo 'image assembly requires root' >&2; exit 1; }

output=$1
base=${2:-}
kernel=${3:-.obj/kernel/amd64.MP/bsd}
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$output" in /*) ;; *) output="$(pwd)/$output" ;; esac
case "$kernel" in /*) ;; *) kernel="$(pwd)/$kernel" ;; esac
[ -f "$kernel" ] || { echo "missing kernel: $kernel" >&2; exit 1; }
for tool in hammer2 newfs_hammer2 mount_hammer2 fsck_hammer2; do
	[ -x "$repo/src/sbin/$tool/$tool" ] || {
		echo "missing $tool; run make first" >&2; exit 1;
	}
done

work=$(mktemp -d /tmp/hammer2-install80.XXXXXXXX)
srcvnd=
dstvnd=
srcmounted=no
dstmounted=no
cleanup() {
	if [ "$dstmounted" = yes ]; then umount "$work/dst" || :; fi
	if [ "$srcmounted" = yes ]; then umount "$work/src" || :; fi
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
install -m 555 "$kernel" "$work/dst/bsd.hammer2"
install -m 555 "$kernel" "$payload/bsd.hammer2"
for tool in hammer2 newfs_hammer2 mount_hammer2 fsck_hammer2; do
	install -m 555 "$repo/src/sbin/$tool/$tool" "$payload/hammer2-tools/$tool"
done
cat > "$payload/hammer2-tools/README" <<'EOF'
HAMMER2 tools for OpenBSD 8.0 amd64

The installer boots the stock bsd.rd. The HAMMER2-enabled GENERIC.MP kernel
is /bsd.hammer2 and 8.0/amd64/bsd.hammer2. Its four filesystem utilities are
in 8.0/amd64/hammer2-tools. Copy the kernel to the installed FFS boot
partition and the utilities to the installed system (/sbin for mount_hammer2
and fsck_hammer2, /sbin or /usr/sbin for newfs_hammer2 and hammer2).

The stock bsd.rd cannot mount HAMMER2. To install a HAMMER2 root filesystem,
boot a system with the HAMMER2-enabled kernel, create a partition with fstype
22, run newfs_hammer2, and populate the ROOT PFS with the OpenBSD base set.
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
