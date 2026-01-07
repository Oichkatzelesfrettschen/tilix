#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
schema="$root/docs/pure-d/config.schema.json"

if [[ ! -f "$schema" ]]; then
  echo "Schema not found: $schema" >&2
  exit 1
fi

if [[ -n "${1:-}" ]]; then
  config="$1"
elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
  config="$XDG_CONFIG_HOME/tilix/pure-d.json"
else
  config="$HOME/.config/tilix/pure-d.json"
fi

if [[ ! -f "$config" ]]; then
  if [[ -n "${1:-}" ]]; then
    echo "Config not found: $config" >&2
    exit 1
  fi
  config="$root/docs/pure-d/sample-config.json"
fi

if [[ ! -f "$config" ]]; then
  echo "Config not found: $config" >&2
  exit 1
fi

SCHEMA_PATH="$schema" CONFIG_PATH="$config" python3 - <<'PY'
import json
import os
import sys
from jsonschema import Draft202012Validator

schema_path = os.environ["SCHEMA_PATH"]
config_path = os.environ["CONFIG_PATH"]
with open(schema_path, "r", encoding="utf-8") as f:
    schema = json.load(f)
with open(config_path, "r", encoding="utf-8") as f:
    config = json.load(f)

validator = Draft202012Validator(schema)
errors = sorted(validator.iter_errors(config), key=lambda e: e.path)
if errors:
    print("Config validation failed:")
    for err in errors:
        path = "/".join(str(p) for p in err.path) or "<root>"
        print(f" - {path}: {err.message}")
    sys.exit(1)

print(f"Config validation OK: {config_path}")
PY
