#!/bin/ksh

set -e

DIR=$1
if [ "${DIR}" = "" ]; then
	DIR=$(pwd)
fi

[ -d "${DIR}" ] || exit 1
[ -d /usr/src/sys ] || exit 1
PATCH_FILE=${DIR}/patch/openbsd80.patch
[ -f "${PATCH_FILE}" ] || {
	echo "${PATCH_FILE} does not exist" >&2
	exit 1
}

HAMMER2_DIR=${DIR}/src/sys/fs/hammer2
if [ ! -d "${HAMMER2_DIR}" ]; then
	echo "${HAMMER2_DIR} does not exist"
	exit 1
fi

HAMMER2_LNK=/usr/src/sys/hammer2

ICRC32_REG=${DIR}/src/sys/libkern/icrc32.c
if [ ! -f "${ICRC32_REG}" ]; then
	echo "${ICRC32_REG} does not exist"
	exit 1
fi

ICRC32_LNK=/usr/src/sys/lib/libkern/icrc32.c
for pair in "${HAMMER2_LNK}:${HAMMER2_DIR}" "${ICRC32_LNK}:${ICRC32_REG}"; do
	link=${pair%%:*}
	target=${pair#*:}
	if [ -e "${link}" ] || [ -L "${link}" ]; then
		if [ ! -L "${link}" ] || [ "$(readlink "${link}")" != "${target}" ]; then
			echo "${link} already exists with a different target" >&2
			exit 1
		fi
	fi
done

if patch -C -t -R -d /usr/src -p1 -i "${PATCH_FILE}" >/dev/null 2>&1; then
	echo 'OpenBSD source patch already applied'
else
	if ! patch -C -t -N -d /usr/src -p1 -i "${PATCH_FILE}" >/dev/null 2>&1; then
		echo 'OpenBSD source patch does not apply cleanly; check /usr/src' >&2
		exit 1
	fi
	patch -t -N -d /usr/src -p1 -i "${PATCH_FILE}"
fi

[ -L "${HAMMER2_LNK}" ] || /bin/ln -s "${HAMMER2_DIR}" "${HAMMER2_LNK}"
[ -L "${ICRC32_LNK}" ] || /bin/ln -s "${ICRC32_REG}" "${ICRC32_LNK}"

/bin/ls -l "${HAMMER2_LNK}"
/bin/ls -l "${ICRC32_LNK}"

echo "prep success"
