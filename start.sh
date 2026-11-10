#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
 "") [[ $# == 0 ]] || exit 1; exec "$root/dev/compose.sh" start;;
 --check) [[ $# == 1 ]] || exit 1; exec "$root/dev/compose.sh" config;;
 --test) [[ $# == 1 ]] || exit 1; exec "$root/dev/compose.sh" test;;
 --self-test) [[ $# == 1 ]] || exit 1; exec "$root/dev/compose.sh" self-test;;
 *) echo 'Supported arguments: --check, --test, --self-test, or none' >&2; exit 1;;
esac
