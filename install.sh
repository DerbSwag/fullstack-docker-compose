#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"$root/dev/compose.sh" config --quiet
"$root/dev/compose.sh" pull mysql
"$root/dev/compose.sh" build backend frontend
