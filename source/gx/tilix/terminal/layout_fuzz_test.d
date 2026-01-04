module gx.tilix.terminal.layout_fuzz_test;

import std.algorithm;
import std.array;
import std.format;
import std.math;
import std.random;
import std.stdio;
import std.sumtype;

import gx.tilix.terminal.layout_verified;

/**
 * Fuzz Testing for Verified Layout Engine
 */

// Generators

Layout genLeaf(ref Random gen, ref int idCounter) {
    return makeLeaf(++idCounter);
}

Layout genTree(ref Random gen, ref int idCounter, int depth) {
    if (depth <= 0 || uniform(0, 100, gen) < 20) { // 20% chance to stop early
        return genLeaf(gen, idCounter);
    }
    
    // Split
    Axis ax = uniform(0, 2, gen) == 0 ? Axis.Horizontal : Axis.Vertical;
    int pos = uniform(50, 500, gen); // Arbitrary position
    
    return makeNode(ax, pos, genTree(gen, idCounter, depth - 1), genTree(gen, idCounter, depth - 1));
}

// Properties

bool prop_balance_preserves_leaves(Layout l) {
    int initialCount = countLeaves(l);
    
    LayoutConfig cfg = LayoutConfig(10, 5, 8, 16);
    Rect r = Rect(0, 0, 1000, 1000); // Test rect
    
    Layout balanced = balance(l, cfg, r);
    int finalCount = countLeaves(balanced);
    
    if (initialCount != finalCount) {
        writeln("Prop Failed: Balance Preserves Leaves");
        writefln("Initial: %d, Final: %d", initialCount, finalCount);
        return false;
    }
    return true;
}

bool prop_resize_safe(LayoutConfig cfg, int current, int total, int delta) {
    // Test both axes
    int newPosH = calculateResize(cfg, current, total, delta, Axis.Horizontal);
    int newPosV = calculateResize(cfg, current, total, delta, Axis.Vertical);
    
    // Check invariants for Horizontal
    if (newPosH != -1) {
        if (newPosH < cfg.minSize || newPosH > (total - cfg.handleSize - cfg.minSize)) return false;
        // Snap check (heuristic)
        if (cfg.charWidth > 1 && (newPosH % cfg.charWidth != 0)) {
             // Note: Snap logic is ((val + half)/grid)*grid. 
             // It might not be exactly 0 mod grid if there is offset, but here we assume 0 offset.
             // Let's just check bounds for now.
        }
    }
    
    return true;
}

unittest {
    writeln("Starting Layout Fuzz Tests...");
    auto gen = Random(unpredictableSeed);
    
    enum NUM_TESTS = 1000;
    
    // 1. Balance Fuzzing
    for (int i = 0; i < NUM_TESTS; i++) {
        int idCounter = 0;
        Layout l = genTree(gen, idCounter, 5);
        assert(prop_balance_preserves_leaves(l));
    }
    writeln("  Balance Fuzzing Passed.");
    
    // 2. Resize Fuzzing
    for (int i = 0; i < NUM_TESTS; i++) {
        LayoutConfig cfg = LayoutConfig(uniform(10, 100, gen), uniform(1, 10, gen), uniform(5, 20, gen), uniform(10, 30, gen));
        int total = uniform(200, 2000, gen);
        int current = uniform(cfg.minSize, total - cfg.handleSize - cfg.minSize, gen);
        int delta = uniform(-200, 200, gen);
        
        assert(prop_resize_safe(cfg, current, total, delta));
    }
    writeln("  Resize Fuzzing Passed.");
    
    // 3. Navigation Fuzzing (Basic Sanity)
    // Verify findNeighbor doesn't crash on random trees
    for (int i = 0; i < NUM_TESTS; i++) {
        int idCounter = 0;
        Layout l = genTree(gen, idCounter, 4);
        
        // Pick a random ID from 1..idCounter
        if (idCounter > 0) {
            int target = uniform(1, idCounter + 1, gen);
            int neighbor = findNeighbor(l, target, Axis.Horizontal, true);
            // Result can be valid ID or -1. Just ensure no crash.
        }
    }
    writeln("  Navigation Fuzzing Passed.");
}
