# Boot OpenBSD from a HAMMER2 root filesystem

## Goal and scope

Boot an OpenBSD kernel with HAMMER2 support from an FFS boot partition, mount a HAMMER2 PFS as `/`, reach a login prompt, and survive clean and interrupted reboots. Keep the initial bootloader and kernel image on FFS so this work can focus on the kernel root mount path. Use a disposable VM and disk image until the acceptance checks pass.

The `make kernel` and `make install-kernel` targets build and install `/bsd.hammer2`. The default kernel configuration is `GENERIC.MP`, with a separate `.obj/kernel/${MACHINE}.MP` build directory. This plan tracks the root mount implementation and VM validation; the initial `dk_mountroot()` and `hammer2_mount()` limitations have been addressed in the development tree.

## 1. Record the baseline

- [x] Record the OpenBSD release and architecture, DragonFlyBSD source revision, port commit, kernel configuration, and compiler used for the test: OpenBSD 8.0 amd64, DragonFlyBSD `d37499e259`, port baseline `f4d399e`, `GENERIC.MP`, OpenBSD clang 22.1.6.
- [x] Build the HAMMER2-enabled `GENERIC.MP` kernel with the root mount changes. `make KERNEL_BUILD_DIR=/tmp/hammer2-root-mp-build kernel` completed on OpenBSD 8.0 amd64 and produced `/tmp/hammer2-root-mp-build/bsd`.
- [ ] Confirm `newfs_hammer2`, `mount_hammer2`, `fsck_hammer2`, and `hammer2` build and work on a non-root test volume.
- The four userspace tools build with `make -s` on the target host. `newfs_hammer2` formatted `/dev/rsd1a`, and `mount_hammer2` mounted `/dev/sd1a@ROOT` as a non-root volume in the VM. `fsck_hammer2` and other `hammer2` commands still need runtime checks.
- [ ] Capture a VM boot log with the existing FFS root and `/bsd.hammer2`.
- [ ] Keep a known working kernel and rescue image available on the FFS boot partition.

## 2. Identify HAMMER2 as a root filesystem

- [x] Choose an unused disklabel filesystem type number after checking the target OpenBSD source tree: `FS_HAMMER2 = 22` follows `FS_UDF = 21` in OpenBSD 8.0. Recheck this number when rebasing to another release.
- [x] Add `FS_HAMMER2` and its display name in `/usr/src/sys/sys/disklabel.h`; verify disklabel tools can set and show that type. A `disklabel` built against the patched header set and displayed `HAMMER2` on VM `sd1a`.
- [x] Add a HAMMER2 case to `dk_mountroot()` in `/usr/src/sys/kern/subr_disk.c`, guarded by the HAMMER2 kernel option, that calls `hammer2_mountroot()`.
- [x] Add the required function declaration and kernel configuration dependencies. (`GENERIC.MP` includes `GENERIC`, which enables HAMMER2.)
- [ ] Carry all changes to the OpenBSD base tree in `patch/openbsd80.patch` (or the repository's documented patch mechanism), then confirm `make prep` applies them to a clean matching tree.
- [ ] Verify a kernel without HAMMER2 still builds and its existing root mount behavior is unchanged.

## 3. Implement early HAMMER2 root mounting

- [x] Trace the regular mount path through `hammer2_mount()`, `hammer2_init_devvp()`, volume header loading, and PFS lookup; identify every operation that assumes a mounted root or userspace pointer.
- [x] Refactor common volume and PFS setup so normal mounts and root mounts share validation and cleanup code. (Both now call `hammer2_mount_impl()`.)
- [x] Implement `hammer2_mountroot()` using the kernel-provided `rootdev` block vnode, `vfs_rootmountalloc()`, and the standard mount list/statfs handoff. The root path bypasses pathname lookup and `copyinstr()`; the full MP kernel links. Boot behavior is covered by the separate runtime checks below.
- [ ] Define how the root PFS is selected at boot. Start with a documented `ROOT` label; reject a missing or ambiguous PFS with a useful console error. Decide whether a boot-time override is needed after the first working boot.
- The initial root selection is the `ROOT` PFS on the selected HAMMER2 root partition. The kernel mounts it read-only and prints the selected source on success. A missing `ROOT` label fails with `ENOENT`; duplicate-label handling and a boot-time override remain to be decided after VM testing.
- [ ] Check the root vnode type, mount flags, vnode references, device open/close, and all failure cleanup against the target OpenBSD VFS conventions.
- The root path rejects a non-block vnode, starts read-only, and releases device vnode references on both pre-open and post-open cleanup paths. The VM booted and survived clean and forced reboots; exceptional cleanup paths still need fault testing.
- [x] Confirm the mounted root is initially usable read-only and can be remounted read/write during startup. The console reported the initial read-only mount, startup remounted it, and `mount -u /` plus file writes succeeded.
- `mount_hammer2` accepts both `-u node` and the `-o update special node` form used by OpenBSD `mount(8)`; its rebuild and VM remount passed. Update failures print a valid source name when no special argument was supplied.
- [ ] Ensure kernel diagnostics identify the device, selected PFS, and failure stage without exposing misleading success messages.

## 4. Prepare a disposable boot image

- [x] Create disposable VM disks with separate FFS boot and HAMMER2 root storage: `/tmp/hammer2-root-test.img` is `sd0` (6 GiB, FFS `sd0a`, swap `sd0b`); `/tmp/hammer2-pfs-test.img` is `sd1` (4 GiB, HAMMER2 `sd1a`, type 22, offset 64 sectors).
- [ ] Install boot blocks, `/boot`, `/bsd.hammer2`, `/bsd.rd`, and a known working kernel on the FFS partition.
- [x] Format the HAMMER2 partition and create the `ROOT` PFS using the port's tools (`newfs_hammer2 -s 3G -L ROOT /dev/rsd1a`). The explicit 3 GiB size avoids the formatter rounding the 4 GiB disk beyond its partition end.
- [x] Populate `ROOT` with the matching OpenBSD 8.0 `base80.tgz`, copy the installed `/etc` and `/var`, run `MAKEDEV all`, and install `mount_hammer2` and `fsck_hammer2` in `/sbin`. The VM reached login from this root.
- [x] Create a minimal `/etc/fstab` for the HAMMER2 root and swap. `mount`, `mount -u /`, and startup checks completed in the VM.
- [ ] Keep a way to select the FFS rescue kernel/root at the boot prompt. Do not change the host's default boot configuration during development.

## 5. Boot and validate in stages

- [x] Boot `/bsd.hammer2` with `-a` and explicitly select `sd1a` root and `sd0b` swap.
- [x] Confirm disklabel detection dispatches to `hammer2_mountroot()` and that the intended `ROOT` PFS becomes `/`. The console reported `/dev/sd1a@ROOT`, and `mount` showed `/dev/sd1a on / type hammer2`.
- [x] Confirm `/sbin/init` starts, startup scripts complete, and a login prompt appears on the VM console.
- [ ] Check `mount`, `df`, `stat`, file creation, rename, unlink, directory traversal, and permissions on `/`.
- [x] Confirm the root remounts read/write, changes persist after `sync` and reboot, and clean shutdown works. `/root/h2-root-probe` survived multiple clean reboots.
- [ ] Test several cold boots and clean reboots. Compare on-disk data and inspect console logs for HAMMER2 errors or leaks.
- [x] Force-stop the disposable VM after writing `/root/interrupted-probe`, then cold boot it. The root mounted and reached login; both the new file and earlier data were readable without repair. This is one recovery sample, not a general durability guarantee.
- [ ] Test missing `ROOT` PFS, invalid HAMMER2 header, and wrong disklabel type. Each should fail clearly without mounting the wrong volume.
- [ ] Confirm the FFS rescue path and `/bsd.rd` remain bootable.
- [ ] Run focused regression checks for ordinary HAMMER2 mounts and the userspace tools after root-mount changes.

## 6. Make the boot repeatable

- [ ] Document the tested partition layout, format/population commands, fstab entries, and boot prompt command.
- [ ] Once explicit root selection is reliable, configure the test VM to select `/bsd.hammer2` and the HAMMER2 root by default; document the exact OpenBSD mechanism used.
- [ ] Reboot without manual intervention and confirm the same root device and PFS are mounted.
- [ ] Review the patch for OpenBSD source tree assumptions and commit kernel, patch, and documentation changes with the passing test results.

## Acceptance criteria

- [x] A fresh disposable VM image boots `/bsd.hammer2` from FFS and mounts HAMMER2 `ROOT` as `/`.
- [x] It reaches a login prompt, mounts `/` read/write, and persists changes across clean reboots.
- [x] It recovers from the tested forced power-off without repair; broader failure testing remains open.
- [ ] Missing or invalid root media fails with a clear diagnostic, and the FFS rescue path works.
- [ ] The build, image creation, and boot procedure can be repeated from the documented commands.

## VM run on 2026-11-20

Build a modified OpenBSD 8.0 amd64 installer with `make install80.img`. The
target builds the HAMMER2 `GENERIC.MP` kernel and four userspace tools, fetches
and verifies the official `install80.img` if needed, and writes an expanded
`install80.img` in the repository root. Set `INSTALL80_BASE=/path/to/install80.img`
to reuse an existing release image. The target also builds a custom
`RAMDISK_CD` kernel with HAMMER2 enabled and expands the stock installer
ramdisk to 40 MiB for the patched `disklabel`, HAMMER2 tools, the compressed
install kernel, and their libraries. The image boots this custom `/bsd.rd` by default. The full
`/bsd.hammer2` single-user kernel remains available from the boot prompt;
the unmodified release ramdisk is at `/8.0/amd64/bsd.rd`. The image retains
the release sets, adds
`/bsd.hammer2` and
`/8.0/amd64/bsd.hammer2`, and puts `hammer2`, `newfs_hammer2`,
`mount_hammer2`, and `fsck_hammer2` under `/8.0/amd64/hammer2-tools/`.
The interactive `(I)nstall` workflow now offers a HAMMER2 root option on a
second disk. The first disk receives FFS boot files, and the second disk
receives a 3 GiB HAMMER2 `ROOT` PFS on partition `a`. The install script
mounts HAMMER2 at `/mnt`, installs the selected sets, puts `/bsd.hammer2` and
`/boot` on the FFS partition, and writes an FFS boot configuration that
prompts for the HAMMER2 root device at startup. The second disk must be at
least 4 GiB. The image is
about 928 MiB and needs root access to assemble its boot partitions.

On 2026-11-20, the new install path was exercised in `vmd` with a 2 GiB FFS
boot disk (`sd0`), a 4 GiB HAMMER2 disk (`sd1`), and the custom install image
as set media (`sd2`). The installer formatted `sd1a`, mounted `ROOT` read/write,
and installed `bsd`, `bsd.rd`, and `base80.tgz`. An initial run exposed three
installer assumptions: `printf` was absent from the ramdisk, non-FFS entries
were mounted read-only, and the installer passed `-o async` to HAMMER2. These
were fixed in `script/enable-hammer2-install.py`. The run also found that
`installboot -cr` expects boot files under the install root; the script now
passes explicit boot stage paths for the separate FFS partition. That last
correction was applied manually in the VM before booting and is included in
the rebuilt `install80.img`. The resulting VM booted `/bsd.hammer2` from FFS with `-a`,
mounted `sd1a@ROOT`, reached login, and showed `/` on HAMMER2 and `/bootfs`
on FFS. The ramdisk reservation is now 40 MiB to hold the compressed kernel.

The final `install80.img` was then tested from scratch in `vmd` with fresh
2 GiB and 4 GiB target disks. The interactive installer completed without
manual repair and printed its success message. A cold boot from those target
disks mounted `sd1a@ROOT` as `/`, mounted `sd0a` at `/bootfs`, and reached
login. Both installed HAMMER2 mount and fsck tools were present. A file
written under `/root` persisted across a clean reboot. The boot configuration
still prompts for `sd1a` and `sd0b`; automatic root device selection remains
future work. The VM reported `reorder_kernel` failure because this development
kernel has no matching relink set.

On 2026-11-20, `make KERNEL_BUILD_DIR=/tmp/hammer2-root-mp-build
INSTALL80_BASE=/tmp/install80.orig.img install80.img` completed. The image
contained the matching HAMMER2 kernel and all four tools. In `vmd`, it booted
to the custom kernel's single-user shell with a blank second disk as `sd1`.
The custom `bsd.rd` also booted to the installer prompt in `vmd`. Its shell
created `/dev/sd1` nodes, formatted, mounted, and created a `ROOT` PFS on a
blank second disk. The tested sequence was `disklabel -E sd1` (create `a` at offset 64, type
`HAMMER2`), `newfs_hammer2 /dev/rsd1a`,
`mount_hammer2 /dev/sd1a@DATA /mnt/h2`, and
`hammer2 -s /mnt/h2 pfs-create ROOT`. The `ROOT` PFS also mounted at `/mnt2`.

The test used OpenBSD `vmd` with two sparse raw images in `/tmp`. On the host, start `vmd`, create a 6 GiB FFS disk and a 4 GiB HAMMER2 disk with `vmctl create -s`, then start the VM with `vmctl start -d /tmp/hammer2-root-test.img -d /tmp/hammer2-pfs-test.img -m 2G -L hammer2-root-test`. The first disk was installed from the OpenBSD 8.0 `bsd` and `base80.tgz` sets using `/bsd.rd`; `/bsd` remains the FFS rescue kernel. Set `tty com0` in the FFS `/etc/boot.conf` and enable the `console` getty in `/etc/ttys` for `vmctl console` access. Place the built kernel at `/bsd.hammer2` on FFS. The tested FFS boot configuration is:

```
set tty com0
boot /bsd.hammer2 -a
```

The stock release `disklabel` tool does not know type 22. Build `disklabel` from the matching OpenBSD source with the patched `/usr/src/sys/sys/disklabel.h`, then set `sd1a` to type `HAMMER2`, offset 64 sectors, and the remaining disk space. In the guest, use:

```
newfs_hammer2 -s 3G -L ROOT /dev/rsd1a
mount_hammer2 /dev/sd1a@ROOT /mnt/h2
tar -xzpf /usr/base80.tgz -C /mnt/h2
cp -Rp /etc/. /mnt/h2/etc/
cp -Rp /var/. /mnt/h2/var/
cd /mnt/h2/dev && ./MAKEDEV all
```

Copy the built `mount_hammer2` and `fsck_hammer2` to `/mnt/h2/sbin`. Copying `/var` can report errors for live Unix sockets; those sockets are recreated at boot. The HAMMER2 root's `/etc/fstab` contains:

```
319b6f97787efae6.b none swap sw
/dev/sd1a@ROOT / hammer2 rw 1 0
```

Unmount `/mnt/h2`, boot `/bsd.hammer2 -a`, answer `sd1a` for root and `sd0b` for swap. The last tested kernel initialized time from the RTC, reported `/dev/sd1a@ROOT mounted read-only`, completed startup, and reached login without HAMMER2 errors. `dev_mkdb` succeeded after advisory locking support was added. `reorder_kernel` still reports failure because this development kernel has no matching relink set; investigate separately. The VM was shut down cleanly, and both disposable images remain in `/tmp` for further tests. The FFS image does not yet contain `/bsd.rd`; use the host's `/bsd.rd` with `vmctl start -b` for rescue testing.

## Key code locations

- `src/sys/fs/hammer2/hammer2_vfsops.c`: mount and proposed root mount entry point.
- `src/sys/fs/hammer2/hammer2_ondisk.c`: device lookup and volume initialization.
- `patch/openbsd80.patch`: integration changes to the OpenBSD source tree.
- `/usr/src/sys/kern/subr_disk.c`: disklabel-driven root mount dispatch.
- `/usr/src/sys/sys/disklabel.h`: filesystem type definitions and names.
- `/usr/src/sys/ufs/ffs/ffs_vfsops.c`: OpenBSD root mount handoff example.
