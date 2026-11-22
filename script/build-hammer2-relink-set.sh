#!/bin/sh
# Package the exact objects used for the custom kernel as an installer set.
set -eu

[ "$#" -eq 3 ] || {
	echo "usage: $0 kernel-build-dir set-output work-dir" >&2
	exit 1
}
build=$1
output=$2
work=$3
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kit=$(basename "$build")
stage=$work/relink-stage
dest=$stage/usr/share/relink/kernel/$kit
mkdir -p "$dest" "$stage/usr/libexec" "$stage/etc"
printf '%s\n' "$kit" >"$stage/etc/hammer2-relink-kernel"

for file in "$build"/*.o "$build/Makefile" "$build/makegap.sh" \
    "$build/ld.script"; do
	[ -f "$file" ] || { echo "missing relink input: $file" >&2; exit 1; }
	ln "$file" "$dest/$(basename "$file")" 2>/dev/null ||
	    cp -p "$file" "$dest/$(basename "$file")"
done

# The generated Makefile normally replaces the stock /bsd. Leave it untouched
# and install the relinked image on the FFS boot volume.
sed '/^newinstall:/,/^$/s@/var/db/kernel\.SHA256 /bsd@/var/db/kernel.hammer2.SHA256 /bootfs/bsd.hammer2@; /^newinstall:/,/^$/s@bsd /bsd@bsd /bootfs/bsd.hammer2@' \
    "$build/Makefile" >"$dest/Makefile.new"
mv "$dest/Makefile.new" "$dest/Makefile"
grep -q 'install -F -m 700 bsd /bootfs/bsd.hammer2' "$dest/Makefile"
grep -q 'sha256 -h /var/db/kernel.hammer2.SHA256 /bootfs/bsd.hammer2' "$dest/Makefile"
install -m 555 "$repo/script/reorder-hammer2-kernel.sh" \
    "$stage/usr/libexec/reorder_kernel"
tar -C "$stage" -czf "$output" .
