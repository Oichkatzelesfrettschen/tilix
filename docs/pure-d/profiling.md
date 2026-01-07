# Pure D Profiling (GC/Allocations)

Use druntime GC profiling to get allocation stats from headless tests.

## Run GC profile
```
./scripts/pure-d/run_gc_profile.sh
```

Notes:
- Uses `--DRT-gcopt=profile:1` to print GC stats on exit.
- The settings are documented in the druntime config module
  (`core/gc/config.d` in the D toolchain).
- For render-loop allocation audits, combine this with `pure-d-nogc` builds.
