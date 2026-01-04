module gx.tilix.terminal.layout_verified;

import std.algorithm;
import std.math;
import std.sumtype; // Synergistic alignment with Coq Inductive Types

/**
 * Configuration Context (Config)
 */
struct LayoutConfig {
    int minSize;    // Minimum width/height
    int handleSize; // Thickness of splitter
    int charWidth;  // Snap grid width
    int charHeight; // Snap grid height

    this(int minSize, int handleSize, int charWidth = 8, int charHeight = 16) {
        this.minSize = minSize;
        this.handleSize = handleSize;
        this.charWidth = charWidth;
        this.charHeight = charHeight;
    }
}

/**
 * Geometric Types
 */
struct Rect {
    int x, y, w, h;
}

enum Axis { Horizontal, Vertical }

/**
 * Layout Data Structures (Algebraic Data Types)
 */
struct Leaf {
    int id;
}

struct Node {
    Axis axis;
    int position; // Pixel position of split
    Layout* child1; // Pointer for recursion in struct
    Layout* child2;
}

/**
 * The Layout SumType
 * Matches Coq: Inductive Layout := Leaf ... | Node ...
 */
alias Layout = SumType!(Leaf, Node);

// Factory methods for compatibility/ease of use
Layout makeLeaf(int id) {
    return Layout(Leaf(id));
}

Layout makeNode(Axis axis, int pos, Layout c1, Layout c2) {
    // We need to allocate children on heap for recursive structure
    // SumType constructor is explicit, so we use a helper to copy to heap
    Layout* heapAlloc(Layout val) {
        Layout* ptr = new Layout;
        *ptr = val;
        return ptr;
    }
    
    return Layout(Node(axis, pos, heapAlloc(c1), heapAlloc(c2)));
}

// Property Helpers for Session.d compatibility
// These mimic the old class properties but use pattern matching.

bool isLeaf(Layout l) {
    return l.match!((Leaf _) => true, (Node _) => false);
}

bool isNode(Layout l) {
    return l.match!((Leaf _) => false, (Node _) => true);
}

int id(Layout l) {
    return l.match!((Leaf leaf) => leaf.id, (Node _) => -1);
}

Axis axis(Layout l) {
    return l.match!((Leaf _) => Axis.Horizontal, (Node n) => n.axis);
}

int position(Layout l) {
    return l.match!((Leaf _) => 0, (Node n) => n.position);
}

Layout child1(Layout l) {
    return l.match!((Leaf _) => makeLeaf(-1), (Node n) => *n.child1);
}

Layout child2(Layout l) {
    return l.match!((Leaf _) => makeLeaf(-1), (Node n) => *n.child2);
}

/**
 * Helper: Count number of leaves (terminals) in a subtree
 */
int countLeaves(Layout l) {
    return l.match!(
        (Leaf leaf) => 1,
        (Node node) => countLeaves(*node.child1) + countLeaves(*node.child2)
    );
}

/**
 * Balancing Logic
 * Relayouts the tree such that space is distributed proportionally to the number of leaves.
 */
Layout balance(Layout l, LayoutConfig cfg, Rect r) {
    return l.match!(
        (Leaf leaf) => makeLeaf(leaf.id),
        (Node node) {
            int size = (node.axis == Axis.Horizontal) ? r.w : r.h;
            int w1 = countLeaves(*node.child1);
            int w2 = countLeaves(*node.child2);
            int totalLeaves = w1 + w2;

            // Calculate ideal split position based on weights
            int available = size - cfg.handleSize;
            if (totalLeaves == 0) totalLeaves = 1; 
            int pos = cast(int)((cast(long)available * w1) / totalLeaves);

            Rect r1, r2;
            if (node.axis == Axis.Horizontal) {
                r1 = Rect(r.x, r.y, pos, r.h);
                r2 = Rect(r.x + pos + cfg.handleSize, r.y, r.w - pos - cfg.handleSize, r.h);
            } else {
                r1 = Rect(r.x, r.y, r.w, pos);
                r2 = Rect(r.x, r.y + pos + cfg.handleSize, r.w, r.h - pos - cfg.handleSize);
            }

            return makeNode(node.axis, pos, balance(*node.child1, cfg, r1), balance(*node.child2, cfg, r2));
        }
    );
}

/**
 * Helper: Find leaf in subtree closest to the "edge" we came from.
 */
int findClosestLeaf(Layout l, Axis relevantAxis, bool minimize) {
    return l.match!(
        (Leaf leaf) => leaf.id,
        (Node node) {
            if (node.axis == relevantAxis) {
                return minimize ? findClosestLeaf(*node.child1, relevantAxis, minimize) 
                                : findClosestLeaf(*node.child2, relevantAxis, minimize);
            } else {
                // Orthogonal -> Default to minimizing (Top/Left)
                return findClosestLeaf(*node.child1, relevantAxis, minimize);
            }
        }
    );
}

/**
 * Find a neighbor in a specific direction.
 * Returns -1 if no neighbor found.
 */
int findNeighbor(Layout l, int currentId, Axis dirAxis, bool forward) {
    // Step 1: Find path to current node
    // Structure to hold the path: List of (Node, isChild1?)
    struct PathStep {
        Node node;
        bool isChild1; // true if we went left/child1, false if child2
    }
    
    PathStep[] path;
    
    bool findPathRecursive(Layout current, int targetId) {
        return current.match!(
            (Leaf leaf) => leaf.id == targetId,
            (Node node) {
                // Try Child 1
                path ~= PathStep(node, true);
                if (findPathRecursive(*node.child1, targetId)) return true;
                path.length--; // Pop
                
                // Try Child 2
                path ~= PathStep(node, false);
                if (findPathRecursive(*node.child2, targetId)) return true;
                path.length--; // Pop
                
                return false;
            }
        );
    }
    
    if (!findPathRecursive(l, currentId)) return -1;
    
    // Step 2: Backtrack
    foreach_reverse (step; path) {
        if (step.node.axis != dirAxis) continue;
        
        // If moving Forward (Right/Down), we must be in Child1 to move to Child2
        if (forward && step.isChild1) {
            // Found split! Go to Child2
            return findClosestLeaf(*step.node.child2, dirAxis, true); // Minimize (Left-most of Right tree)
        }
        // If moving Backward (Left/Up), we must be in Child2 to move to Child1
        if (!forward && !step.isChild1) {
            // Found split! Go to Child1
            return findClosestLeaf(*step.node.child1, dirAxis, false); // Maximize (Right-most of Left tree)
        }
    }
    
    return -1;
}

/**
 * Validity Predicate (Recursive)
 */
bool isValid(Layout l, LayoutConfig cfg, Rect r) {
    return l.match!(
        (Leaf leaf) => r.w >= cfg.minSize && r.h >= cfg.minSize,
        (Node node) {
            int size = (node.axis == Axis.Horizontal) ? r.w : r.h;
            
            // 1. Structural integrity (Local)
            if (node.position < cfg.minSize) return false;
            if (node.position + cfg.handleSize + cfg.minSize > size) return false;

            // 2. Recursive Validity
            Rect r1, r2;
            if (node.axis == Axis.Horizontal) {
                r1 = Rect(r.x, r.y, node.position, r.h);
                r2 = Rect(r.x + node.position + cfg.handleSize, r.y, r.w - node.position - cfg.handleSize, r.h);
            } else {
                r1 = Rect(r.x, r.y, r.w, node.position);
                r2 = Rect(r.x, r.y + node.position + cfg.handleSize, r.w, r.h - node.position - cfg.handleSize);
            }

            return isValid(*node.child1, cfg, r1) && isValid(*node.child2, cfg, r2);
        }
    );
}

/**
 * Snap-to-Grid Logic (Verified)
 * Rounds 'val' to the nearest multiple of 'grid'.
 */
long snapToGrid(long val, long grid) {
    if (grid <= 1) return val;
    long half = grid / 2;
    return ((val + half) / grid) * grid;
}

/**
 * Resize Logic (Formal Definition with Snap-to-Grid)
 * Returns -1 if invalid.
 */
int calculateResize(LayoutConfig cfg, int currentPos, int totalSize, int delta, Axis axis) {
    long rawTarget = cast(long)currentPos + delta;
    
    // Determine grid size based on axis
    long grid = (axis == Axis.Horizontal) ? cfg.charWidth : cfg.charHeight;
    
    // Apply Snapping
    long snappedPos = snapToGrid(rawTarget, grid);
    
    // Bounds
    long minPos = cfg.minSize;
    long maxPos = totalSize - cfg.handleSize - cfg.minSize;
    
    if (snappedPos < minPos) return -1;
    if (snappedPos > maxPos) return -1;
    
    return cast(int)snappedPos;
}

unittest {
    // Config: Min 10px, Handle 5px, Char 8x16
    LayoutConfig cfg = LayoutConfig(10, 5, 8, 16);
    
    // Test Resize Calculation
    // Total 100px.
    
    // 1. Horizontal Snap (Grid 8)
    // Current 50. Delta 3. Target 53.
    // 53 snap 8 -> 53+4 = 57 / 8 = 7 * 8 = 56.
    assert(calculateResize(cfg, 50, 100, 3, Axis.Horizontal) == 56);
    
    // 2. Vertical Snap (Grid 16)
    // Current 50. Delta 3. Target 53.
    // 53 snap 16 -> 53+8 = 61 / 16 = 3 * 16 = 48.
    assert(calculateResize(cfg, 50, 100, 3, Axis.Vertical) == 48);
    
    // 3. Bounds Check
    // Max Pos = 100 - 5 - 10 = 85.
    // Try snap to 88 (Grid 8 * 11).
    // Target 88 > 85. Invalid.
    assert(calculateResize(cfg, 85, 100, 3, Axis.Horizontal) == -1); // 85+3=88 -> snap 88 -> 88 > 85
}
