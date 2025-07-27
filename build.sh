#!/bin/bash

set -eu

declare -r revision="$(git rev-parse --short HEAD)"

declare -r workdir="${PWD}"

declare -r install_prefix='/tmp/gdb'

declare -r gmp_tarball='/tmp/gmp.tar.xz'
declare -r gmp_directory='/tmp/gmp-6.3.0'

declare -r mpfr_tarball='/tmp/mpfr.tar.xz'
declare -r mpfr_directory='/tmp/mpfr-4.2.2'

declare -r gdb_tarball='/tmp/gdb.tar.xz'
declare -r gdb_directory='/tmp/gdb-16.3'

declare -r optflags='-w -O2'
declare -r linkflags='-Xlinker -s'

declare -r max_jobs='40'

declare -ra targets=(
	'x86_64-unknown-linux-gnu'
	'ia64-unknown-linux-gnu'
	'mips-unknown-linux-gnu'
	'mips64el-unknown-linux-gnuabi64'
	'mipsel-unknown-linux-gnu'
	'powerpc-unknown-linux-gnu'
	'powerpc64le-unknown-linux-gnu'
	's390-unknown-linux-gnu'
	's390x-unknown-linux-gnu'
	# 'sparc-unknown-linux-gnu'
	'alpha-unknown-linux-gnu'
	'aarch64-unknown-linux-gnu'
	'arm-unknown-linux-gnueabi'
	'arm-unknown-linux-gnueabihf'
	'hppa-unknown-linux-gnu'
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
		--url 'https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz' \
		--retry '30' \
		--retry-all-errors \
		--retry-delay '0' \
		--retry-max-time '0' \
		--location \
		--silent \
		--output "${gmp_tarball}"
	
	tar \
		--directory="$(dirname "${gmp_directory}")" \
		--extract \
		--file="${gmp_tarball}"
fi

if ! [ -f "${mpfr_tarball}" ]; then
	curl \
		--url 'https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.2.tar.xz' \
		--retry '30' \
		--retry-all-errors \
		--retry-delay '0' \
		--retry-max-time '0' \
		--location \
		--silent \
		--output "${mpfr_tarball}"
	
	tar \
		--directory="$(dirname "${mpfr_directory}")" \
		--extract \
		--file="${mpfr_tarball}"
fi

if ! [ -f "${gdb_tarball}" ]; then
	curl \
		--url 'https://ftp.gnu.org/gnu/gdb/gdb-16.3.tar.xz' \
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
	
	echo 'UNSUPPORTED=1' >> "${gdb_directory}/gdbserver/configure.srv"
fi

[ -d "${gmp_directory}/build" ] || mkdir "${gmp_directory}/build"

cd "${gmp_directory}/build"
rm --force --recursive ./*

../configure \
	--host="${CROSS_COMPILE_TRIPLET}" \
	--prefix="${install_prefix}" \
	--enable-shared \
	--disable-static \
	CFLAGS="${optflags}" \
	CXXFLAGS="${optflags}" \
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
	CFLAGS="${optflags}" \
	CXXFLAGS="${optflags}" \
	LDFLAGS="${linkflags}"

make all --jobs
make install

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
		--without-static-standard-libraries \
		CFLAGS="${optflags}" \
		CXXFLAGS="${optflags}" \
		LDFLAGS="${linkflags}"
	
	make all --jobs="${max_jobs}"
	make install
	
	ls "${install_prefix}/bin"
	
	patchelf --set-rpath '$ORIGIN/../lib' "${install_prefix}/bin/${target}-gdb"
	
	[ -f "${install_prefix}/bin/${target}-gdbserver" ] && patchelf --set-rpath '$ORIGIN/../lib' "${install_prefix}/bin/${target}-gdbserver"
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
