#!/bin/bash

set -eu

declare -r workdir="${PWD}"

declare -r install_prefix='/tmp/gdb'

declare -r gmp_tarball='/tmp/gmp.tar.xz'
declare -r gmp_directory='/tmp/gmp-6.3.0'

declare -r mpfr_tarball='/tmp/mpfr.tar.xz'
declare -r mpfr_directory='/tmp/mpfr-4.2.2'

declare -r gdb_tarball='/tmp/gdb.tar.xz'
declare -r gdb_directory='/tmp/gdb-source'

declare -r zlib_tarball='/tmp/zlib.tar.gz'
declare -r zlib_directory='/tmp/zlib-develop'

declare -r zstd_tarball='/tmp/zstd.tar.gz'
declare -r zstd_directory='/tmp/zstd-dev'

declare -r ccflags='-w -O2'
declare -r linkflags='-Xlinker -s'

declare -r max_jobs='15'

declare -ra targets=(
	'x86_64-unknown-linux-gnu'
	'aarch64-unknown-linux-gnu'
	'arm-unknown-linux-gnueabi'
	'arm-unknown-linux-gnueabihf'
	'i386-unknown-linux-gnu'
	'x86_64-unknown-linux-android'
	'i686-unknown-linux-android'
	'aarch64-unknown-linux-android'
	'riscv64-unknown-linux-android'
	'armv5-unknown-linux-androideabi'
	'armv7-unknown-linux-androideabi'
	'mips64el-unknown-linux-android'
	'mipsel-unknown-linux-android'
)

declare -r PKG_CONFIG_PATH="${install_prefix}/lib/pkgconfig"
declare -r PKG_CONFIG_LIBDIR="${PKG_CONFIG_PATH}"
declare -r PKG_CONFIG_SYSROOT_DIR="${install_prefix}"

declare -r ZSTD_CFLAGS="-I${install_prefix}/include"
declare -r ZSTD_LIBS="-L${install_prefix}/lib -lzstd"

export \
	PKG_CONFIG_PATH \
	PKG_CONFIG_LIBDIR \
	PKG_CONFIG_SYSROOT_DIR \
	ZSTD_CFLAGS \
	ZSTD_LIBS

declare build_type="${1}"

if [ -z "${build_type}" ]; then
	build_type='native'
fi

declare is_native='0'

if [ "${build_type}" = 'native' ]; then
	is_native='1'
fi

set +u

if [ -z "${CROSS_COMPILE_TRIPLET}" ]; then
	declare CROSS_COMPILE_TRIPLET=''
fi

set -u

declare -r \
	build_type \
	is_native

if ! [ -f "${gmp_tarball}" ]; then
	curl \
		--url 'https://mirrors.kernel.org/gnu/gmp/gmp-6.3.0.tar.xz' \
		--retry '30' \
		--retry-delay '0' \
		--retry-all-errors \
		--retry-max-time '0' \
		--location \
		--silent \
		--output "${gmp_tarball}"
	
	tar \
		--directory="$(dirname "${gmp_directory}")" \
		--extract \
		--file="${gmp_tarball}"
	
	patch --directory="${gmp_directory}" --strip='1' --input="${workdir}/submodules/obggcc/patches/0001-Remove-hardcoded-RPATH-and-versioned-SONAME-from-libgmp.patch"
	
	echo -e 'all:\ninstall:' > "${gmp_directory}/tests/Makefile.in"
	echo -e 'all:\ninstall:' > "${gmp_directory}/demos/Makefile.in"
	echo -e 'all:\ninstall:' > "${gmp_directory}/doc/Makefile.in"
fi

if ! [ -f "${mpfr_tarball}" ]; then
	curl \
		--url 'https://mirrors.kernel.org/gnu/mpfr/mpfr-4.2.2.tar.xz' \
		--retry '30' \
		--retry-delay '0' \
		--retry-all-errors \
		--retry-max-time '0' \
		--location \
		--silent \
		--output "${mpfr_tarball}"
	
	tar \
		--directory="$(dirname "${mpfr_directory}")" \
		--extract \
		--file="${mpfr_tarball}"
	
	patch --directory="${mpfr_directory}" --strip='1' --input="${workdir}/submodules/obggcc/patches/0001-Remove-hardcoded-RPATH-and-versioned-SONAME-from-libmpfr.patch"
fi

if ! [ -f "${zlib_tarball}" ]; then
	curl \
		--url 'https://github.com/madler/zlib/archive/develop.tar.gz' \
		--retry '30' \
		--retry-all-errors \
		--retry-delay '0' \
		--retry-max-time '0' \
		--location \
		--silent \
		--output "${zlib_tarball}"
	
	tar \
		--directory="$(dirname "${zlib_directory}")" \
		--extract \
		--file="${zlib_tarball}"
	
	patch --directory="${zlib_directory}" --strip='1' --input="${workdir}/submodules/obggcc/patches/0001-Remove-versioned-SONAME-from-libz.patch"
fi

if ! [ -f "${zstd_tarball}" ]; then
	curl \
		--url 'https://github.com/facebook/zstd/archive/dev.tar.gz' \
		--retry '30' \
		--retry-delay '0' \
		--retry-all-errors \
		--retry-max-time '0' \
		--location \
		--silent \
		--output "${zstd_tarball}"
	
	tar \
		--directory="$(dirname "${zstd_directory}")" \
		--extract \
		--file="${zstd_tarball}"
fi

if ! [ -f "${gdb_tarball}" ]; then
	curl \
		--url 'https://github.com/AmanoTeam/binutils-snapshots/releases/latest/download/gdb.tar.xz' \
		--retry '30' \
		--retry-all-errors \
		--retry-delay '0' \
		--retry-max-time '0' \
		--location \
		--silent \
		--output "${gdb_tarball}"
	
	tar \
		--directory="$(dirname "${gdb_directory}")" \
		--extract \
		--file="${gdb_tarball}"
	
	mv "${install_prefix}" "${gdb_directory}"
	
	echo 'UNSUPPORTED=1' >> "${gdb_directory}/gdbserver/configure.srv"
	
	patch --directory="${gdb_directory}" --strip='1' --input="${workdir}/patches/0001-Add-relative-RPATHs-to-GDB-tools.patch"
fi

sed \
	--in-place \
	--regexp-extended \
	's/(hardcode_into_libs)=.*$/\1=no/' \
	"${gdb_directory}/configure"

[ -d "${gmp_directory}/build" ] || mkdir "${gmp_directory}/build"

cd "${gmp_directory}/build"
rm --force --recursive ./*

../configure \
	--host="${CROSS_COMPILE_TRIPLET}" \
	--prefix="${install_prefix}" \
	--enable-shared \
	--disable-static \
	CFLAGS="${ccflags}" \
	CXXFLAGS="${ccflags}" \
	LDFLAGS="${linkflags}"

make all --jobs
make install

[ -d "${mpfr_directory}/build" ] || mkdir "${mpfr_directory}/build"

cd "${mpfr_directory}/build"
rm --force --recursive ./*

../configure \
	--host="${CROSS_COMPILE_TRIPLET}" \
	--prefix="${install_prefix}" \
	--with-gmp="${install_prefix}" \
	--enable-shared \
	--disable-static \
	CFLAGS="${ccflags}" \
	CXXFLAGS="${ccflags}" \
	LDFLAGS="${linkflags}"

make all --jobs
make install

[ -d "${zlib_directory}/build" ] || mkdir "${zlib_directory}/build"

cd "${zlib_directory}/build"
rm --force --recursive ./*

../configure \
	--host="${CROSS_COMPILE_TRIPLET}" \
	--prefix="${install_prefix}" \
	CFLAGS="${ccflags}" \
	CXXFLAGS="${ccflags}" \
	LDFLAGS="${linkflags}"

make all --jobs
make install

unlink "${install_prefix}/lib/libz.a"

[ -d "${zstd_directory}/.build" ] || mkdir "${zstd_directory}/.build"

cd "${zstd_directory}/.build"
rm --force --recursive ./*

declare cmake_flags=''

if [[ "${CROSS_COMPILE_TRIPLET}" = *'-darwin'* ]]; then
	cmake_flags+=' -DCMAKE_SYSTEM_NAME=Darwin'
fi

cmake \
	-S "${zstd_directory}/build/cmake" \
	-B "${PWD}" \
	${cmake_flags} \
	-DCMAKE_C_FLAGS="-DZDICT_QSORT=ZDICT_QSORT_MIN ${ccflags}" \
	-DCMAKE_INSTALL_PREFIX="${install_prefix}" \
	-DBUILD_SHARED_LIBS=ON \
	-DZSTD_BUILD_PROGRAMS=OFF \
	-DZSTD_BUILD_TESTS=OFF \
	-DZSTD_BUILD_STATIC=OFF \
	-DCMAKE_PLATFORM_NO_VERSIONED_SONAME=ON

cmake --build "${PWD}"
cmake --install "${PWD}" --strip

for target in "${targets[@]}"; do
	[ -d "${gdb_directory}/build" ] || mkdir "${gdb_directory}/build"
	
	cd "${gdb_directory}/build"
	rm --force --recursive ./*
	
	../configure \
		--host="${CROSS_COMPILE_TRIPLET}" \
		--target="${target}" \
		--program-prefix="${target}-" \
		--prefix="${install_prefix}" \
		--disable-shared \
		--enable-static \
		--disable-nls \
		--disable-source-highlight \
		--disable-tui \
		--enable-plugins \
		--with-python='no' \
		--with-gmp="${install_prefix}" \
		--with-mpfr="${install_prefix}" \
		--with-system-zlib \
		--without-static-standard-libraries \
		CFLAGS="-I${install_prefix}/include ${ccflags}" \
		CXXFLAGS="-I${install_prefix}/include ${ccflags}" \
		LDFLAGS="-L${install_prefix}/lib ${linkflags}"
	
	make all --jobs="${max_jobs}"
	make install
done

declare cc='gcc'
declare readelf='readelf'

if ! (( is_native )); then
	cc="${CC}"
	readelf="${READELF}"
fi

# Bundle both libstdc++ and libgcc within host tools
if ! (( is_native )); then
	[ -d "${install_prefix}/lib" ] || mkdir "${install_prefix}/lib"
	
	declare name=$(realpath $("${cc}" --print-file-name='libstdc++.so'))
	declare soname=$("${readelf}" -d "${name}" | grep 'SONAME' | sed --regexp-extended 's/.+\[(.+)\]/\1/g')
	
	cp "${name}" "${install_prefix}/lib/${soname}"
	
	declare name=$(realpath $("${cc}" --print-file-name='libgcc_s.so.1'))
	declare soname=$("${readelf}" -d "${name}" | grep 'SONAME' | sed --regexp-extended 's/.+\[(.+)\]/\1/g')
	
	cp "${name}" "${install_prefix}/lib/${soname}"
fi
