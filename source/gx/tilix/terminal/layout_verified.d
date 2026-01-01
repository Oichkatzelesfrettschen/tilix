/**
 * Verified Layout Module (Ported from Coq/OCaml)
 *
 * This module implements the layout logic formally verified in Coq.
 * See verification/Layout.v for the formal specification.
 *
 * Coq Type Mapping:
 * - coq_Rect -> Rect
 * - coq_Layout -> Layout (Algebraic Data Type / Tagged Union)
 */
module gx.tilix.terminal.layout_verified;

import std.algorithm;

/**
 * Geometric Types
 */
struct Rect {
    int x;
    int y;
    int w;
    int h;

    /** Invariant: Dimensions must be positive */
    bool isValid() const {
        return w > 0 && h > 0;
    }

    /** Intersection Logic */
    bool intersects(const Rect other) const {
        return x < other.x + other.w &&
               other.x < x + w &&
               y < other.y + other.h &&
               other.y < y + h;
    }
}

/**
 * Layout Tree Structure (Algebraic Data Type)
 */
class Layout {
    // Tag for the type of node
    enum Type { Window, HSplit, VSplit }
    Type type;

    // Window data
    int windowId;
    Rect windowRect;

    // Split data
    Layout child1;
    Layout child2;
    int ratio; // Percentage 0-100

    // Private constructors for factory methods
    private this(Type t) { type = t; }

    static Layout makeWindow(int id, Rect r) {
        auto l = new Layout(Type.Window);
        l.windowId = id;
        l.windowRect = r;
        return l;
    }

    static Layout makeHSplit(Layout left, Layout right, int r) {
        auto l = new Layout(Type.HSplit);
        l.child1 = left;
        l.child2 = right;
        l.ratio = r;
        return l;
    }

    static Layout makeVSplit(Layout top, Layout bottom, int r) {
        auto l = new Layout(Type.VSplit);
        l.child1 = top;
        l.child2 = bottom;
        l.ratio = r;
        return l;
    }

    /**
     * Calculate total area (Verified Function)
     */
    int area() {
        final switch(type) {
            case Type.Window:
                return windowRect.w * windowRect.h;
            case Type.HSplit:
                return child1.area() + child2.area();
            case Type.VSplit:
                return child1.area() + child2.area();
        }
    }
}

unittest {
    // Test: Area Conservation
    // Corresponds to Coq theorem: split_area_conservation
    auto r1 = Rect(0, 0, 100, 100);
    auto l1 = Layout.makeWindow(1, r1);
    
    auto r2 = Rect(100, 0, 100, 100);
    auto l2 = Layout.makeWindow(2, r2);

    auto split = Layout.makeHSplit(l1, l2, 50);

    assert(l1.area() == 10000);
    assert(l2.area() == 10000);
    assert(split.area() == 20000);
    assert(split.area() == l1.area() + l2.area());
}
