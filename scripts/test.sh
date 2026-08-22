#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/.." && pwd)"

cd "${repository_root}"

aseprite_binary="/Applications/Aseprite.app/Contents/MacOS/aseprite"

if command -v lua5.4 >/dev/null 2>&1; then
  lua5.4 tests/run.lua
elif command -v lua >/dev/null 2>&1; then
  lua tests/run.lua
elif [[ -x "${aseprite_binary}" ]]; then
  "${aseprite_binary}" --batch --script tests/run.lua
else
  echo "Lua 5.4 or Aseprite is required to run the tests." >&2
  exit 1
fi

if [[ -x "${aseprite_binary}" ]]; then
  "${aseprite_binary}" --batch --script tests/aseprite_integration.lua
fi
