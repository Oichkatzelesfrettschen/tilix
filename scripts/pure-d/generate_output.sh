#!/usr/bin/env bash
set -euo pipefail

size_mb="${1:-512}"
bytes=$((size_mb * 1024 * 1024))

if (( bytes <= 0 )); then
  echo "Usage: $0 <size_mb>" >&2
  exit 1
fi

head -c "${bytes}" /dev/zero | tr '\0' 'A'
