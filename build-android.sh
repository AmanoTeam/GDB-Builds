#!/bin/bash

set -eu

declare -r workdir="${PWD}"
declare -r work_root="${GDB_WORK_DIR:-/tmp}"

declare -r install_prefix="${GDB_INSTALL_PREFIX:-${work_root}/gdb}"
declare -r gdb_tarball="${GDB_TARBALL:-${work_root}/gdb.tar.xz}"
declare -r gdb_directory="${GDB_SOURCE_DIR:-${work_root}/gdb-source}"
declare -r build_directory="${GDB_BUILD_DIR:-${gdb_directory}/build-android}"

declare -r ccflags='-D__BIONIC_DEPRECATED_PAGE_SIZE_MACRO -O2'
declare -r max_jobs="${GDB_BUILD_PARALLEL_LEVEL:-$(nproc)}"

: "${PINO_HOME:?Set PINO_HOME to the android-gcc-cross installation directory}"
: "${CROSS_COMPILE_TRIPLET:?Source an android-gcc-cross Autotools environment first}"
: "${CROSS_COMPILE_API_LEVEL:?Source an API-specific android-gcc-cross environment first}"
: "${CROSS_COMPILE_SYSROOT:?CROSS_COMPILE_SYSROOT is required}"

mkdir --parents "${work_root}"

if ! [ -d "${gdb_directory}" ]; then
	if ! [ -f "${gdb_tarball}" ]; then
		curl \
			--url 'https://github.com/AmanoTeam/binutils-snapshots/releases/latest/download/gdb.tar.xz' \
			--retry '30' \
			--retry-all-errors \
			--retry-delay '0' \
			--retry-max-time '0' \
			--location \
			--silent \
			--show-error \
			--fail \
			--output "${gdb_tarball}"
	fi
	
	tar \
		--directory="${work_root}" \
		--extract \
		--file="${gdb_tarball}"
	
	mv "${work_root}/gdb" "${gdb_directory}"
	
	echo 'UNSUPPORTED=1' >> "${gdb_directory}/gdbserver/configure.srv"
	
	patch \
		--directory="${gdb_directory}" \
		--strip='1' \
		--input="${workdir}/patches/0002-Fix-GDB-build-on-Android.patch"
fi

declare -r apt="${PINO_HOME}/bin/${CROSS_COMPILE_TRIPLET}${CROSS_COMPILE_API_LEVEL}-apt"
declare -ra packages=(
	'libgmp-static'
	'libmpfr-static'
	'libexpat-static'
	'liblzma-static'
)

for package in "${packages[@]}"; do
	"${apt}" --assume-yes --install="${package}"
done

declare -r dependency_prefix="${CROSS_COMPILE_SYSROOT}/lib/nouzen/sysroot/usr"
declare -r quarantine="${CROSS_COMPILE_SYSROOT}/lib/nouzen/shared-libs-disabled"
declare -ra libraries=(
	'libgmp'
	'libgmpxx'
	'libmpfr'
	'libexpat'
	'liblzma'
)

# Prefer the static archives installed above. Libtool otherwise selects the
# shared libraries or their .la files, which contain Termux-specific paths.
mkdir --parents "${quarantine}"

for library in "${libraries[@]}"; do
	for file in "${dependency_prefix}/lib/${library}".so* "${dependency_prefix}/lib/${library}".la; do
		[ -e "${file}" ] || [ -L "${file}" ] || continue
		mv --force "${file}" "${quarantine}/"
	done
done

export PINO_STATIC_RUNTIME='true'
export CC_FOR_BUILD='gcc'
export CXX_FOR_BUILD='g++'

declare -r build_triplet="$("${gdb_directory}/config.guess")"

rm --force --recursive "${build_directory}"
mkdir --parents "${build_directory}"
cd "${build_directory}"

"${gdb_directory}/configure" \
	--build="${build_triplet}" \
	--host="${CROSS_COMPILE_TRIPLET}" \
	--target="${CROSS_COMPILE_TRIPLET}" \
	--prefix="${install_prefix}" \
	--with-gmp="${dependency_prefix}" \
	--with-mpfr="${dependency_prefix}" \
	--with-expat \
	--with-lzma \
	--without-system-zlib \
	--without-system-readline \
	--without-python \
	--without-guile \
	--without-xxhash \
	--disable-source-highlight \
	--disable-tui \
	--disable-nls \
	--disable-gdbserver \
	--disable-binutils \
	--disable-gas \
	--disable-ld \
	--disable-gold \
	--disable-gprof \
	--disable-gprofng \
	--disable-sim \
	--disable-tests \
	--disable-werror \
	CFLAGS="${ccflags}" \
	CXXFLAGS="${ccflags}"

make --jobs="${max_jobs}" all-gdb
make install-gdb

"${READELF}" -d "${install_prefix}/bin/gdb" | grep 'NEEDED'
