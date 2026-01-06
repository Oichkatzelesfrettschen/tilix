# Pure D Performance Harness

Goal: validate throughput and correctness without GTK/VTE in the Pure D backend.

Prereqs:
- `vttest` for correctness (see `docs/INSTALL_REQUIREMENTS.md`).
- `hyperfine` optional for repeatable timing.

Steps:
1) Build and launch:
   - `scripts/pure-d/run_perf_harness.sh`
2) In the Pure D terminal, generate output:
   - `scripts/pure-d/generate_output.sh 512`
3) Run correctness suite:
   - `vttest`

Notes:
- Increase the output size for more stress (e.g., `1024` or `2048`).
- Use `hyperfine` to compare runs if installed.
