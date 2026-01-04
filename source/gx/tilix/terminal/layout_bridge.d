/**
 * Layout Bridge (Verified <-> GTK)
 *
 * This module acts as an adapter to convert the runtime GTK widget tree
 * into the Verified Layout structure defined in Coq.
 *
 * It avoids circular dependencies between Session and LayoutVerified.
 */
module gx.tilix.terminal.layout_bridge;

import gtk.Container;
import gtk.Widget;
import gtk.Paned;
import gtk.Box;
import std.typecons; // For Nullable

import gx.tilix.terminal.terminal;
import gx.tilix.terminal.layout_verified; // Global functions makeLeaf, makeNode
import gx.gtk.util;

class LayoutBridge {
    
    /**
     * Reconstructs the Verified Layout Tree from a GTK Container root.
     * Returns Nullable!Layout (isNull if widget is null or invalid).
     */
    static Nullable!Layout fromWidget(Widget widget) {
        if (widget is null) return Nullable!Layout.init;

        // Case 1: Terminal
        if (cast(Terminal)widget !is null) {
            Terminal t = cast(Terminal)widget;
            return Nullable!Layout(makeLeaf(cast(int)t.terminalID));
        }

        // Case 2: Paned (Split)
        if (cast(Paned)widget !is null) {
            Paned p = cast(Paned)widget;
            
            Widget child1Widget = p.getChild1();
            Widget child2Widget = p.getChild2();
            
            // Recurse
            Nullable!Layout l1 = fromWidget(unwrapBox(child1Widget));
            Nullable!Layout l2 = fromWidget(unwrapBox(child2Widget));
            
            if (l1.isNull || l2.isNull) return Nullable!Layout.init;
            
            int pos = p.getPosition();
            
            if (p.getOrientation() == Orientation.HORIZONTAL) {
                return Nullable!Layout(makeNode(Axis.Horizontal, pos, l1.get, l2.get));
            } else {
                return Nullable!Layout(makeNode(Axis.Vertical, pos, l1.get, l2.get));
            }
        }

        // Case 3: Box (Shim)
        if (cast(Box)widget !is null) {
            return fromWidget(unwrapBox(widget));
        }

        return Nullable!Layout.init;
    }

    /**
     * Helper to peek inside the Box shims used by Tilix.
     */
    private static Widget unwrapBox(Widget w) {
        Box b = cast(Box)w;
        if (b is null) return w;
        
        Widget[] children = gx.gtk.util.getChildren!(Widget)(b, false);
        if (children.length > 0) {
            return children[0];
        }
        return null;
    }
}
