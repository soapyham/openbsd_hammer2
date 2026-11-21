#!/bin/sh
# Build an amd64 RAMDISK_CD kernel with HAMMER2 and room for its utilities.
set -eu

[ "$#" -eq 2 ] || { echo "usage: $0 source-dir build-dir" >&2; exit 1; }
source_dir=$1
build_dir=$2
config_source="$source_dir/arch/amd64/conf/RAMDISK_CD"
[ -f "$config_source" ] || { echo "missing $config_source" >&2; exit 1; }
[ -f "$source_dir/hammer2/hammer2.h" ] || {
	echo 'HAMMER2 kernel sources are missing; run make prep' >&2; exit 1;
}
mkdir -p "$build_dir"
config_file="$build_dir/RAMDISK_CD.HAMMER2"
new_config="$build_dir/RAMDISK_CD.HAMMER2.new"
awk '
    $1 == "option" && $2 ~ /^MINIROOTSIZE=/ {
        print "option\t\tMINIROOTSIZE=81920"
        next
    }
    { print }
    $1 == "option" && $2 == "FFS" { print "option\t\tHAMMER2" }
' "$config_source" > "$new_config"
if ! cmp -s "$new_config" "$config_file"; then
    # config(8) does not track changed option values in object dependencies.
    rm -f "$build_dir/rd.o"
fi
mv "$new_config" "$config_file"
config -b "$build_dir" -s "$source_dir" "$config_file"
make -C "$build_dir"
