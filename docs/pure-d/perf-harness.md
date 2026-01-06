# Pure D Performance Harness

Goal: validate throughput and correctness without GTK/VTE in the Pure D backend.

Prereqs:
- `vttest` for correctness (see `docs/INSTALL_REQUIREMENTS.md`).
- `hyperfine` optional for repeatable timing.

Steps:
1) Build and launch:
   - `scripts/pure-d/run_perf_harness.sh`
2) (Optional) run headless tests:
   - `./build/pure/tilix-pure-tests`
3) In the Pure D terminal, generate output:
   - `scripts/pure-d/generate_output.sh 512`
4) Run correctness suite:
   - `vttest`
5) Optional: compare runs with hyperfine:
   - `hyperfine --runs 5 "scripts/pure-d/generate_output.sh 512"`

Notes:
- Increase the output size for more stress (e.g., `1024` or `2048`).
- Use `hyperfine` to compare runs if installed.
- `tilix-pure-nogc` is useful for isolating render-loop allocations.
- CI: set `TILIX_CI_PERF=1` to run the harness script via `scripts/ci/dub-build.sh`.
