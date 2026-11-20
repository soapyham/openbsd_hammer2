# Boot OpenBSD from a HAMMER2 root filesystem

## Goal and scope

Boot an OpenBSD kernel with HAMMER2 support from an FFS boot partition, mount a HAMMER2 PFS as `/`, reach a login prompt, and survive clean and interrupted reboots. Keep the initial bootloader and kernel image on FFS so this work can focus on the kernel root mount path. Use a disposable VM and disk image until the acceptance checks pass.

The existing `make kernel` and `make install-kernel` targets build and install `/bsd.hammer2`. The default kernel configuration is `GENERIC.MP`, with a separate `.obj/kernel/${MACHINE}.MP` build directory. They do not make a HAMMER2 root bootable yet. The current `dk_mountroot()` selects FFS, ext2fs, or cd9660 from the disklabel filesystem type; HAMMER2 has no root mount entry point. Normal `hammer2_mount()` needs userspace mount arguments and a pathname lookup, which are unavailable during early root mounting.

## 1. Record the baseline

- [x] Record the OpenBSD release and architecture, DragonFlyBSD source revision, port commit, and kernel configuration used for the test: OpenBSD 8.0 amd64, DragonFlyBSD `d37499e259`, port baseline `f4d399e`, `GENERIC.MP`. Record toolchain versions with the final build log.
- [ ] Run `make kernel` and confirm the HAMMER2-enabled kernel builds before modifying the root mount path.
- [ ] Confirm `newfs_hammer2`, `mount_hammer2`, `fsck_hammer2`, and `hammer2` build and work on a non-root test volume.
- [ ] Capture a VM boot log with the existing FFS root and `/bsd.hammer2`.
- [ ] Keep a known working kernel and rescue image available on the FFS boot partition.

## 2. Identify HAMMER2 as a root filesystem

- [ ] Choose an unused disklabel filesystem type number after checking the target OpenBSD source tree and document the choice.
- [ ] Add `FS_HAMMER2` and its display name in `/usr/src/sys/sys/disklabel.h`; verify disklabel tools can set and show that type.
- [ ] Add a HAMMER2 case to `dk_mountroot()` in `/usr/src/sys/kern/subr_disk.c`, guarded by the HAMMER2 kernel option, that calls `hammer2_mountroot()`.
- [ ] Add the required function declaration and kernel configuration dependencies.
- [ ] Carry all changes to the OpenBSD base tree in `patch/openbsd80.patch` (or the repository's documented patch mechanism), then confirm `make prep` applies them to a clean matching tree.
- [ ] Verify a kernel without HAMMER2 still builds and its existing root mount behavior is unchanged.

## 3. Implement early HAMMER2 root mounting

- [ ] Trace the regular mount path through `hammer2_mount()`, `hammer2_init_devvp()`, volume header loading, and PFS lookup; identify every operation that assumes a mounted root or userspace pointer.
- [ ] Refactor common volume and PFS setup so normal mounts and root mounts share validation and cleanup code.
- [ ] Implement `hammer2_mountroot()` using the kernel-provided `rootdev` block vnode, `vfs_rootmountalloc()`, and the standard mount list/statfs handoff. Do not call pathname lookup or `copyinstr()` from this path.
- [ ] Define how the root PFS is selected at boot. Start with a documented `ROOT` label; reject a missing or ambiguous PFS with a useful console error. Decide whether a boot-time override is needed after the first working boot.
- [ ] Check the root vnode type, mount flags, vnode references, device open/close, and all failure cleanup against the target OpenBSD VFS conventions.
- [ ] Confirm the mounted root is initially usable read-only and can be remounted read/write during startup.
- [ ] Ensure kernel diagnostics identify the device, selected PFS, and failure stage without exposing misleading success messages.

## 4. Prepare a disposable boot image

- [ ] Create a VM disk with an OpenBSD disklabel and separate FFS boot and HAMMER2 root partitions; record the exact partition letters and device names used.
- [ ] Install boot blocks, `/boot`, `/bsd.hammer2`, `/bsd.rd`, and a known working kernel on the FFS partition.
- [ ] Format the HAMMER2 partition and create the `ROOT` PFS using the port's tools.
- [ ] Populate `ROOT` with a complete matching OpenBSD base system, including `/sbin/init`, `/bin/ksh`, required shared libraries, `/etc`, and device nodes.
- [ ] Create a minimal `/etc/fstab` for the HAMMER2 root and any separate boot/swap partitions. Check how `mount`, `mount -u /`, and boot-time filesystem checks handle the new root type.
- [ ] Keep a way to select the FFS rescue kernel/root at the boot prompt. Do not change the host's default boot configuration during development.

## 5. Boot and validate in stages

- [ ] Boot `/bsd.hammer2` with `-a` and explicitly select the HAMMER2 root partition.
- [ ] Confirm disklabel detection dispatches to `hammer2_mountroot()` and that the intended `ROOT` PFS becomes `/`.
- [ ] Confirm `/sbin/init` starts, startup scripts complete, and a login prompt appears on the VM console.
- [ ] Check `mount`, `df`, `stat`, file creation, rename, unlink, directory traversal, and permissions on `/`.
- [ ] Confirm the root remounts read/write, changes persist after `sync` and reboot, and clean shutdown works.
- [ ] Test several cold boots and clean reboots. Compare on-disk data and inspect console logs for HAMMER2 errors or leaks.
- [ ] Test an interrupted VM boot or forced power-off on a disposable image; verify recovery and document any repair procedure.
- [ ] Test missing `ROOT` PFS, invalid HAMMER2 header, and wrong disklabel type. Each should fail clearly without mounting the wrong volume.
- [ ] Confirm the FFS rescue path and `/bsd.rd` remain bootable.
- [ ] Run focused regression checks for ordinary HAMMER2 mounts and the userspace tools after root-mount changes.

## 6. Make the boot repeatable

- [ ] Document the tested partition layout, format/population commands, fstab entries, and boot prompt command.
- [ ] Once explicit root selection is reliable, configure the test VM to select `/bsd.hammer2` and the HAMMER2 root by default; document the exact OpenBSD mechanism used.
- [ ] Reboot without manual intervention and confirm the same root device and PFS are mounted.
- [ ] Review the patch for OpenBSD source tree assumptions and commit kernel, patch, and documentation changes with the passing test results.

## Acceptance criteria

- [ ] A fresh disposable VM image boots `/bsd.hammer2` from FFS and mounts HAMMER2 `ROOT` as `/`.
- [ ] It reaches a login prompt, mounts `/` read/write, and persists changes across clean reboots.
- [ ] It recovers from the tested interrupted reboot, or the remaining recovery limitation is documented before any real installation.
- [ ] Missing or invalid root media fails with a clear diagnostic, and the FFS rescue path works.
- [ ] The build, image creation, and boot procedure can be repeated from the documented commands.

## Key code locations

- `src/sys/fs/hammer2/hammer2_vfsops.c`: mount and proposed root mount entry point.
- `src/sys/fs/hammer2/hammer2_ondisk.c`: device lookup and volume initialization.
- `patch/openbsd80.patch`: integration changes to the OpenBSD source tree.
- `/usr/src/sys/kern/subr_disk.c`: disklabel-driven root mount dispatch.
- `/usr/src/sys/sys/disklabel.h`: filesystem type definitions and names.
- `/usr/src/sys/ufs/ffs/ffs_vfsops.c`: OpenBSD root mount handoff example.
