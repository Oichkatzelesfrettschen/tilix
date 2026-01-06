#!/usr/bin/env bash
set -euo pipefail

app_path="build/pure/tilix-pure"
out_dir="dist/tilix-pure"
lib_dir="${out_dir}/lib"

if [[ ! -f "${app_path}" ]]; then
  echo "Missing ${app_path}. Build first with: DFLAGS=-w dub build --config=pure-d" >&2
  exit 1
fi

rm -rf "${out_dir}"
mkdir -p "${lib_dir}"

cp "${app_path}" "${out_dir}/tilix-pure"

missing=0
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
done < <(ldd "${app_path}")

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
