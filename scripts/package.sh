#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/.." && pwd)"
output_directory="${1:-${repository_root}/dist}"
package_name="AsepriteAnimationList.aseprite-extension"
package_files=(
  "package.json"
  "main.lua"
  "animation-list.aseprite-keys"
  "LICENSE"
)

mkdir -p "${output_directory}"
output_directory="$(cd "${output_directory}" && pwd)"
artifact_path="${output_directory}/${package_name}"

jq -e '
  .name == "aseprite-animation-list" and
  (.version | test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")) and
  .contributes.scripts[0].path == "./main.lua" and
  .contributes.keys[0].path == "./animation-list.aseprite-keys"
' "${repository_root}/package.json" >/dev/null

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/aseprite-animation-list.XXXXXX")"
cleanup() {
  if [[ -n "${temporary_directory:-}" && -d "${temporary_directory}" ]]; then
    rm -rf -- "${temporary_directory}"
  fi
}
trap cleanup EXIT

for relative_path in "${package_files[@]}"; do
  if [[ ! -f "${repository_root}/${relative_path}" ]]; then
    echo "Missing package file: ${relative_path}" >&2
    exit 1
  fi
  cp "${repository_root}/${relative_path}" "${temporary_directory}/${relative_path}"
  touch -t 198001010000 "${temporary_directory}/${relative_path}"
done

rm -f -- "${artifact_path}"
(
  cd "${temporary_directory}"
  zip -X -9 -q "${artifact_path}" "${package_files[@]}"
)

unzip -tq "${artifact_path}" >/dev/null
printf '%s\n' "${artifact_path}"
