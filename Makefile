SUBDIRS = src
KERNEL_SRC_DIR ?= /usr/src/sys
KERNEL_CONFIG ?= ${KERNEL_SRC_DIR}/arch/${MACHINE}/conf/GENERIC.MP
KERNEL_BUILD_DIR ?= ${.CURDIR}/.obj/kernel/${MACHINE}.MP
RAMDISK_BUILD_DIR ?= ${.CURDIR}/.obj/kernel/${MACHINE}.RAMDISK.HAMMER2
INSTALL80_BASE ?=
SERIAL_CONSOLE ?= no

.PHONY: all clean kernel ramdisk-kernel install-kernel fetch-src $(SUBDIRS)

all: $(SUBDIRS)
$(SUBDIRS):
	$(MAKE) -C $@
clean:
	for dir in $(SUBDIRS); do \
		$(MAKE) -C $$dir $@; \
	done
# Fetch and verify the OpenBSD 8.0 source archives before building.
# The installer also needs the disklabel sources from src.tar.gz.
fetch-src:
	@if [ "$$(id -u)" -eq 0 ]; then \
		sh ./script/fetch-openbsd-src.sh /usr/src; \
	else \
		doas sh ./script/fetch-openbsd-src.sh /usr/src; \
	fi
kernel:
	@test -f ${KERNEL_SRC_DIR}/hammer2/hammer2.h || { echo "HAMMER2 sources missing from ${KERNEL_SRC_DIR}; run make prep" >&2; exit 1; }
	@test -f ${KERNEL_SRC_DIR}/lib/libkern/icrc32.c || { echo "HAMMER2 icrc32.c missing from ${KERNEL_SRC_DIR}; run make prep" >&2; exit 1; }
	mkdir -p ${KERNEL_BUILD_DIR}
	config -b ${KERNEL_BUILD_DIR} -s ${KERNEL_SRC_DIR} ${KERNEL_CONFIG}
	$(MAKE) -C ${KERNEL_BUILD_DIR}
ramdisk-kernel:
	sh ./script/build-ramdisk-kernel.sh ${KERNEL_SRC_DIR} ${RAMDISK_BUILD_DIR}
install-kernel: kernel
	@if [ "$$(id -u)" -eq 0 ]; then \
		install -o root -g wheel -m 700 ${KERNEL_BUILD_DIR}/bsd /bsd.hammer2; \
	else \
		doas install -o root -g wheel -m 700 ${KERNEL_BUILD_DIR}/bsd /bsd.hammer2; \
	fi

# Set INSTALL80_BASE to an existing OpenBSD 8.0 amd64 image to skip the download.
install80.img: kernel ramdisk-kernel all
	@if [ "$$(id -u)" -eq 0 ]; then \
		sh ./script/install80-img.sh "$@" "${INSTALL80_BASE}" "${KERNEL_BUILD_DIR}/bsd" "${RAMDISK_BUILD_DIR}/bsd" "${SERIAL_CONSOLE}"; \
	else \
		doas sh ./script/install80-img.sh "$@" "${INSTALL80_BASE}" "${KERNEL_BUILD_DIR}/bsd" "${RAMDISK_BUILD_DIR}/bsd" "${SERIAL_CONSOLE}"; \
	fi

install: all
	@if [ "$$(id -u)" -eq 0 ]; then ksh -x ./script/install.sh; else doas ksh -x ./script/install.sh; fi
uninstall:
	@if [ "$$(id -u)" -eq 0 ]; then ksh -x ./script/uninstall.sh; else doas ksh -x ./script/uninstall.sh; fi
prep:
	@if [ "$$(id -u)" -eq 0 ]; then ksh -x ./script/prep.sh; else doas ksh -x ./script/prep.sh; fi
unprep:
	@if [ "$$(id -u)" -eq 0 ]; then ksh -x ./script/unprep.sh; else doas ksh -x ./script/unprep.sh; fi
