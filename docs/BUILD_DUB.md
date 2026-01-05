# DUB Build Guide

## Build
```
DFLAGS="-w" dub build --build=release
```

## Tests
```
DFLAGS="-w" dub test --force
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

## Notes
- Warnings are treated as errors via DUB build options.
- Strict builds require `DFLAGS="-w"`; set `TILIX_ALLOW_WARNINGS=1` to bypass.
- Use `--force` to ensure DUB executes post-build commands.
