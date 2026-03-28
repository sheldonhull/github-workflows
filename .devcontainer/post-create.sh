#!/usr/bin/env bash
set -euo pipefail

# Install aqua for local tool management
curl -sSfL https://raw.githubusercontent.com/aquaproj/aqua-installer/main/aqua-installer | bash -s -- -v v2.53.3
export PATH="${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}/bin:$PATH"

# Install actionlint for workflow validation
go install github.com/rhysd/actionlint/cmd/actionlint@latest

echo "Agent environment ready."
