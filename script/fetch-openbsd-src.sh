#!/bin/sh
# Install the OpenBSD 8.0 release sources needed for the installer build.
set -eu

dest=${1:-/usr/src}
mirror=${OPENBSD_MIRROR:-https://cdn.openbsd.org/pub/OpenBSD}
url=${mirror%/}/8.0
key=/etc/signify/openbsd-80-base.pub

[ "$(id -u)" -eq 0 ] || { echo 'source installation requires root' >&2; exit 1; }
[ -f "$key" ] || { echo "missing release key: $key" >&2; exit 1; }
case "$dest" in
/*) [ "$dest" != / ] && [ "$dest" != /usr ] || exit 1 ;;
*) echo 'source destination must be an absolute path' >&2; exit 1 ;;
esac
if [ -e "$dest" ] && [ -n "$(ls -A "$dest")" ]; then
	echo "$dest already contains OpenBSD sources; refusing to overwrite them" >&2
	exit 1
fi

work=$(mktemp -d /tmp/openbsd80-src.XXXXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM

for file in src.tar.gz sys.tar.gz SHA256.sig; do
	ftp -o "$work/$file" "$url/$file"
done
(cd "$work" && signify -C -q -p "$key" -x SHA256.sig \
    src.tar.gz sys.tar.gz)

mkdir -p "$dest"
tar -xzf "$work/src.tar.gz" -C "$dest"
tar -xzf "$work/sys.tar.gz" -C "$dest"
echo "OpenBSD 8.0 sources installed in $dest"
