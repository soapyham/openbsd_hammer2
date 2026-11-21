#!/usr/bin/env python3
"""Adapt the OpenBSD 8.0 installer in the expanded ramdisk."""
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
s = p.read_text()

def replace(old, new):
    global s
    if s.count(old) != 1:
        raise SystemExit(f"unexpected OpenBSD install.sub: {old[:60]!r}")
    s = s.replace(old, new)

anchor = "\tfor _mp in $(bsort $FSENT); do\n"
addition = '''\t# The standard layout created an FFS root on the boot disk. Move the
\t# installed system to HAMMER2 while retaining FFS boot files.
\tif [[ $HAMMER2_INSTALL != no ]]; then
\t\tif [[ $HAMMER2_INSTALL == same ]]; then
\t\t\tHAMMER2_DISK=$ROOTDISK
\t\t\tHAMMER2_PART=d
\t\telse
\t\t\twhile :; do
\t\t\t\task_which "disk" "will hold the HAMMER2 root" \\
\t\t\t\t    '$(rmel $ROOTDISK $(get_dkdevs))'
\t\t\t\tHAMMER2_DISK=$resp
\t\t\t\t[[ -n $HAMMER2_DISK && $HAMMER2_DISK != $ROOTDISK ]] && break
\t\t\tdone
\t\t\tHAMMER2_PART=a
\t\t\tmake_dev $HAMMER2_DISK
\t\t\techo "Configure partition a as HAMMER2 on $HAMMER2_DISK."
\t\t\tdisklabel -E $HAMMER2_DISK
\t\tfi
\t\tif ! disklabel $HAMMER2_DISK | grep -q "^  $HAMMER2_PART: .*HAMMER2 "; then
\t\t\techo "HAMMER2 partition $HAMMER2_PART is required."
\t\t\texit 1
\t\tfi
\t\tnewfs_hammer2 -L ROOT \\
\t\t    /dev/r${HAMMER2_DISK}${HAMMER2_PART} || exit 1
\t\tfor _entry in $FSENT; do
\t\t\tcase $_entry in /!*) HAMMER2_BOOTDEV=${_entry#*!};; esac
\t\tdone
\t\t[[ -n $HAMMER2_BOOTDEV ]] || exit 1
\t\tHAMMER2_FSENT=
\t\tfor _entry in $FSENT; do
\t\t\t[[ $_entry == /!$HAMMER2_BOOTDEV ]] ||
\t\t\t    HAMMER2_FSENT="$HAMMER2_FSENT $_entry"
\t\tdone
\t\tFSENT=$HAMMER2_FSENT
\t\tROOTDEV=${HAMMER2_DISK}${HAMMER2_PART}
\t\techo "/dev/${ROOTDEV}@ROOT / hammer2 rw 1 0" >>/tmp/i/fstab
\t\techo "$HAMMER2_BOOTDEV /bootfs ffs rw,nodev 1 2" >>/tmp/i/fstab
\tfi

'''
replace(anchor, addition + anchor)
replace("\t[[ $_disk != $ROOTDISK ]] && return\n\n\twhile $AI; do", '''\t[[ $_disk != $ROOTDISK ]] && return

\tif [[ $HAMMER2_INSTALL == same ]]; then
\t\tcat > /tmp/i/hammer2.layout <<EOF
/ 512M 0%
swap 128M 0%
EOF
\t\techo "Creating 512M FFS boot, 128M swap, and HAMMER2 root on $_disk."
\t\tdisklabel -T /tmp/i/hammer2.layout -F $_f -w -A $_disk || return
\t\tdisklabel -E $_disk <<EOF
a d


HAMMER2
q
y
EOF
\t\tdisklabel $_disk | grep -q '^  d: .*HAMMER2 ' || return
\t\treturn
\tfi

\twhile $AI; do''')
replace("\tget_rootinfo\n\n\tencrypt_root", '''\tget_rootinfo

\tHAMMER2_INSTALL=no
\tif ! $AI; then
\t\twhile :; do
\t\t\task "HAMMER2 root? (no, same disk, second disk)" no
\t\t\tcase $resp in
\t\t\t[nN]*) HAMMER2_INSTALL=no; break;;
\t\t\t[sS][aA]*) HAMMER2_INSTALL=same; break;;
\t\t\t[sS][eE]*) HAMMER2_INSTALL=second; break;;
\t\t\tesac
\t\tdone
\tfi

\tencrypt_root''')
replace("\tmd_installboot $ROOTDISK\n\n\tchmod og-rwx", '''\tif [[ $HAMMER2_INSTALL != no ]]; then
\t\t# installboot reads /boot from FFS and puts EFI loaders on the ESP.
\t\tmkdir -p /mnt/bootfs/etc /mnt/bootfs/usr/mdec
\t\tcp /boot /mnt/bootfs/boot
\t\tif disk_has $ROOTDISK gpt efisys; then
\t\t\tcp /mnt/usr/mdec/BOOTIA32.EFI \\
\t\t\t    /mnt/usr/mdec/BOOTX64.EFI /mnt/bootfs/usr/mdec/ || exit 1
\t\tfi
\t\tinstallboot -r /mnt/bootfs $ROOTDISK \\
\t\t    /mnt/usr/mdec/biosboot /mnt/bootfs/boot || exit 1
\t\tcp /sbin/mount_hammer2 /mnt/sbin/mount_hammer2
\t\tcp /sbin/fsck_hammer2 /mnt/sbin/fsck_hammer2
\t\tcp /sbin/hammer2 /mnt/sbin/hammer2
\t\tcp /sbin/newfs_hammer2 /mnt/sbin/newfs_hammer2
\telse
\t\tmd_installboot $ROOTDISK
\tfi

\tchmod og-rwx''')
replace("\tsha256 /mnt/bsd |", '''\tif [[ $HAMMER2_INSTALL != no ]]; then
\t\tgzip -dc /bsd.hammer2.gz > /mnt/bootfs/bsd.hammer2 || exit 1
\t\tchmod 700 /mnt/bootfs/bsd.hammer2
\t\tcat > /mnt/bootfs/etc/boot.conf <<EOF
boot /bsd.hammer2
EOF
\tfi

\tsha256 /mnt/bsd |''')
replace("\t\t_msg=$(mount -v -t $_fstype $_async -o $_opt $_dev $_mp) ||", '''\t\t_mountopt=$_async
\t\t[[ $_fstype == hammer2 ]] && _mountopt=
\t\t_msg=$(mount -v -t $_fstype $_mountopt -o $_opt $_dev $_mp) ||''')
replace("\t\t[[ $_fstype == ffs ]] && _mode=rw || _mode=ro",
        "\t\t[[ $_fstype == ffs || $_fstype == hammer2 ]] && _mode=rw || _mode=ro")
p.write_text(s)
