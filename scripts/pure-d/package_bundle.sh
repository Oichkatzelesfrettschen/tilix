#!/usr/bin/env bash
set -euo pipefail

app_path="build/pure/tilix-pure"
nogc_path="build/pure/tilix-pure-nogc"
out_dir="dist/tilix-pure"
lib_dir="${out_dir}/lib"
include_nogc=0

if [[ "${1:-}" == "--include-nogc" ]]; then
  include_nogc=1
fi

if [[ ! -f "${app_path}" ]]; then
  echo "Missing ${app_path}. Build first with: DFLAGS=-w dub build --config=pure-d" >&2
  exit 1
fi

rm -rf "${out_dir}"
mkdir -p "${lib_dir}"

cp "${app_path}" "${out_dir}/tilix-pure"

if (( include_nogc )); then
  if [[ -f "${nogc_path}" ]]; then
    cp "${nogc_path}" "${out_dir}/tilix-pure-nogc"
  else
    echo "Missing ${nogc_path}. Build first with: DFLAGS=-w dub build --config=pure-d-nogc" >&2
    exit 1
  fi
fi

missing=0
collect_libs() {
  local target="$1"
  while read -r line; do
    if [[ "${line}" == *"not found"* ]]; then
      echo "Missing library: ${line}" >&2
      missing=1
      continue
    fi
    lib_path="$(echo "${line}" | awk '/=> \\/|\\// {print $3}')"
    if [[ -n "${lib_path}" && -f "${lib_path}" ]]; then
      cp -n "${lib_path}" "${lib_dir}/"
    fi
  done < <(ldd "${target}")
}

collect_libs "${app_path}"
if (( include_nogc )); then
  collect_libs "${nogc_path}"
fi

cat > "${out_dir}/run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="${DIR}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec "${DIR}/tilix-pure" "$@"
EOF
chmod +x "${out_dir}/run.sh"

if (( missing )); then
  echo "Bundle completed with missing libraries. See output above." >&2
  exit 1
fi

echo "Bundle created at ${out_dir}"
