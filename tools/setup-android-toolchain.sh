#!/bin/bash

set -eu

declare -r repository='AmanoTeam/android-gcc-cross'
declare -r artifact_name='x86_64-unknown-linux-gnu'
declare -r destination='/tmp/android-gcc-cross'
declare -r artifact_directory='/tmp/android-gcc-cross-artifact'
declare -r release_url="https://github.com/${repository}/releases/latest/download/${artifact_name}.tar.xz"

declare archive="/tmp/${artifact_name}.tar.xz"
declare downloaded='0'

# Prefer the release, but fall back to the newest usable CI artifact when a
# failed toolchain build has published an empty release archive.
if curl \
	--connect-timeout '10' \
	--retry '15' \
	--retry-all-errors \
	--fail \
	--silent \
	--show-error \
	--location \
	--url "${release_url}" \
	--output "${archive}" && \
	[ "$(stat --format='%s' "${archive}")" -gt '1048576' ] && \
	tar --file="${archive}" --list > /dev/null; then
	downloaded='1'
fi

if (( ! downloaded )); then
	if ! gh auth status > /dev/null 2>&1; then
		echo 'GitHub CLI authentication is required to download CI artifacts.' >&2
		exit '1'
	fi
	
	rm --force --recursive "${artifact_directory}"
	mkdir --parents "${artifact_directory}"
	
	for run_id in $(gh run list \
		--repo "${repository}" \
		--workflow 'build.yml' \
		--status 'success' \
		--limit '30' \
		--json 'databaseId' \
		--jq '.[].databaseId'); do
		declare artifact_id
		
		artifact_id="$(gh api \
			"repos/${repository}/actions/runs/${run_id}/artifacts?per_page=100" \
			--jq ".artifacts[] | select(.name == \"${artifact_name}\" and .size_in_bytes > 1048576 and (.expired | not)) | .id" \
			| head --lines='1')"
		
		[ -n "${artifact_id}" ] || continue
		
		gh run download "${run_id}" \
			--repo "${repository}" \
			--name "${artifact_name}" \
			--dir "${artifact_directory}"
		
		archive="${artifact_directory}/${artifact_name}.tar.xz"
		downloaded='1'
		break
	done
fi

if (( ! downloaded )); then
	echo 'Unable to find a usable android-gcc-cross toolchain archive.' >&2
	exit '1'
fi

if [ -f "${archive}.sha256" ]; then
	(
		cd "$(dirname "${archive}")"
		sha256sum --check "$(basename "${archive}").sha256"
	)
fi

rm --force --recursive "${destination}"
tar --directory="$(dirname "${destination}")" --extract --file="${archive}"
