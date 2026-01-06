# Pure D Packaging (Bundle)

Goal: create a self-contained bundle with shared libraries alongside `tilix-pure`.

Script:
```sh
scripts/pure-d/package_bundle.sh
```

Output:
- `dist/tilix-pure/tilix-pure`
- `dist/tilix-pure/lib/` (bundled shared libs)
- `dist/tilix-pure/run.sh` (sets `LD_LIBRARY_PATH` and launches)

Optional:
```sh
scripts/pure-d/package_bundle.sh --include-nogc
```
Adds `dist/tilix-pure/tilix-pure-nogc`.

Notes:
- This is a lightweight bundle, not a full AppImage.
- Use `ldd build/pure/tilix-pure` to audit missing libs if the script reports any.
