# DUB Build Guide

## Build
```
DFLAGS="-w" dub build --build=release
```

## Pure D backend
```
DFLAGS="-w" dub build --build=release --config=pure-d
```

## Pure D (LTO, LDC only)
```
DFLAGS="-w" dub build --build=pure-lto --config=pure-d
```

## Pure D strict @nogc render path
```
DFLAGS="-w" dub build --build=release --config=pure-d-nogc
```

## Tests
```
DFLAGS="-w" dub test --force
```

## Pure D headless tests
```
DFLAGS="-w" dub build --config=pure-d-tests
./build/pure/tilix-pure-tests
```

## Install
```
DFLAGS="-w" dub build --build=release --config=install --force
```

Or:
```
sudo ./install.sh
```

## Uninstall
```
DFLAGS="-w" dub build --config=uninstall --force
```

Or:
```
sudo ./uninstall.sh
```

## Resource Prep Outputs
`scripts/dub/prepare-resources.sh` stages artifacts in `build/dub/`.

## Benchmarks
```
dub run --build=release --config=bench-scroll
```

## CI helper
```
scripts/ci/dub-build.sh
```

## Notes
- Warnings are treated as errors via DUB build options.
- Strict builds require `DFLAGS="-w"`; set `TILIX_ALLOW_WARNINGS=1` to bypass.
- Use `--force` to ensure DUB executes post-build commands.
- `pure-d-nogc` enables `PURE_D_STRICT_NOGC`, which avoids cache allocations in the render loop.
