# Phase 5 Performance Baseline

## Design Targets

- **VTParser throughput**: <500 microseconds per 4KB of PTY data
- **Minimum throughput**: >8 MB/s
- **Full-screen update**: <100ms for 80x24 terminal
- **Memory allocations on hot path**: Zero (lock-free design)

## Methodology

### Profiling Tools
1. **Linux perf**: For CPU profiling and cycle counting
   ```bash
   perf record -g ./build/tilix
   perf report
   ```

2. **valgrind cachegrind**: For cache behavior analysis
   ```bash
   valgrind --tool=cachegrind ./build/tilix
   cg_annotate cachegrind.out.*
   ```

3. **Address Sanitizer (ASAN)**: For memory error detection
   ```bash
   dub build --recipe=dub-asan.json --build=asan --compiler=ldc2
   ```

### Test Scenarios

**Scenario 1: Plain ASCII Text (Control)**
- Input: 4KB of ASCII characters
- Expected: ~200MB/s throughput, <100μs per 4KB
- Profile: Minimal branching, cache-friendly state machine

**Scenario 2: Heavy ANSI Sequences**
- Input: 2KB text + 2KB color/style sequences (50/50 split)
- Expected: ~100MB/s throughput, <200μs per 4KB
- Profile: Sequence parser load, parameter collection overhead

**Scenario 3: UTF-8 Heavy Workload**
- Input: Mixed ASCII + multi-byte UTF-8 sequences
- Expected: ~100MB/s throughput (UTF-8 decoding overhead)
- Profile: Multi-byte character handling, state tracking

**Scenario 4: Mixed Realistic Workload**
- Input: Typical terminal output mix (80% text, 10% color, 10% control)
- Expected: ~120MB/s throughput, <170μs per 4KB
- Profile: Representative of real-world terminal usage

**Scenario 5: Stress Test**
- Input: Burst of 64KB from fast-scrolling output
- Expected: No memory leaks, no frame drops >5%
- Profile: Queue saturation, thread contention

## Performance Expectations

### State Machine Dispatch
- **Baseline**: <50ns per byte
- **Implementation**: Simple lookup table in VTParser
- **Verification**: perf stat for instruction count

### UTF-8 Decoding
- **Baseline**: ~5ns per byte (vectorizable)
- **Implementation**: Inline state tracking during parsing
- **Verification**: CPU cache behavior via valgrind

### CSI Parameter Collection
- **Baseline**: ~10ns per byte
- **Implementation**: Dynamic array accumulation with atomic operations
- **Verification**: perf profiling of parameter parsing hot loop

## Continuous Monitoring

### Metrics to Track
1. **Throughput (MB/s)**: Total bytes / elapsed time
2. **Time per 4KB**: Normalized to 4KB blocks regardless of payload size
3. **Events per microsecond**: Parser event generation rate
4. **Memory allocations**: Should be zero on hot path
5. **Cache misses**: L1, L2, L3 via valgrind cachegrind
6. **CPU utilization**: Per-thread load distribution

### Baseline Measurements

**Build Configuration**: Release build with DFLAGS='-w'
**Compiler**: DMD (default)
**Test Date**: 2026-01-05

| Scenario | Input Size | Elapsed Time (μs) | Throughput (MB/s) | Status |
|----------|-----------|------------------|------------------|--------|
| Plain ASCII | 4096 | Baseline target | >200 | To measure |
| ANSI Heavy | 4096 | Baseline target | >100 | To measure |
| UTF-8 Heavy | 4096 | Baseline target | >100 | To measure |
| Mixed Realistic | 4096 | Baseline target | >120 | To measure |

## Profiling Commands

### Quick Baseline
```bash
rdmd -release scripts/benchmark_vtparser.d 100 4096
```

### Full CPU Profiling
```bash
# Record with call graph
perf record -g ./build/tilix
perf report

# Get hot functions
perf top
```

### Cache Analysis
```bash
# Run with cachegrind
valgrind --tool=cachegrind ./build/tilix

# Annotate hot cache paths
cg_annotate cachegrind.out.* --sort=D1mr,LL | head -50
```

### Memory Error Detection
```bash
# Build with ASAN
dub build --recipe=dub-asan.json --build=asan --compiler=ldc2

# Run with ASAN output
./build/tilix 2>&1 | grep -i "sanitizer"
```

## Success Criteria for Phase 5 Deployment

- [x] VTParser unit tests pass (20/20 tests)
- [x] Integration tests pass (10+ tests covering threading, queueing)
- [x] Build succeeds with strict warnings (-w flag)
- [ ] VTParser achieves >8 MB/s throughput (baseline measurement)
- [ ] ASAN build detects no new memory leaks
- [ ] Lock-free queue under thread contention shows <1% drop rate
- [ ] Frame update latency <100ms for typical workloads

## Future Optimization Opportunities

1. **SIMD vectorization**: UTF-8 decoding could use SIMD for parallel byte checking
2. **Branch prediction tuning**: Reorder state machine cases by frequency
3. **Allocation pooling**: Pre-allocate for common sequence patterns
4. **Lazy evaluation**: Defer parameter array construction for single-parameter sequences

---

**Last Updated**: 2026-01-05
**Phase**: 5 (IO Thread Integration - Deployment)
**Status**: Baseline Documentation Complete
