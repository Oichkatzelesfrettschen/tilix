# DUB Build Guide

## Build
```
dub build --build=release
```

## Tests
```
dub test --force
```

## Install
```
dub build --build=release --config=install --force
```

Or:
```
sudo ./install.sh
```

## Uninstall
```
dub build --config=uninstall --force
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
- Use `--force` to ensure DUB executes post-build commands.
