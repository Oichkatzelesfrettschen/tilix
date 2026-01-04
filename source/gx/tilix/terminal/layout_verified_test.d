
module gx.tilix.terminal.layout_verified_test;

import gx.tilix.terminal.layout_verified;

unittest {
    // Config: Min 10px, Handle 5px
    LayoutConfig cfg = LayoutConfig(10, 5);
    
    // Create a 3-leaf tree: (Leaf1 | (Leaf2 - Leaf3))
    // Structure:
    // Node H
    //  L: Leaf 1
    //  R: Node V
    //      L: Leaf 2
    //      R: Leaf 3
    
    // Initial State: Unbalanced
    // Root total width 200.
    // Left gets 10. Right gets 185.
    // Right (H=100). Top 10. Bottom 85.
    
    Layout l = Layout.makeNode(Axis.Horizontal, 10,
        Layout.makeLeaf(1),
        Layout.makeNode(Axis.Vertical, 10,
            Layout.makeLeaf(2),
            Layout.makeLeaf(3)
        )
    );
    
    // Verify initial count
    assert(l.countLeaves() == 3);
    
    // BALANCE
    // Root (H): Total Width 200. Handle 5. Available 195.
    // Left Leaves: 1. Right Leaves: 2. Total 3.
    // Target Pos = 195 * 1 / 3 = 65.
    
    // Right Child (V): Total Height 100. Handle 5. Available 95.
    // Top Leaves: 1. Bottom Leaves: 1. Total 2.
    // Target Pos = 95 * 1 / 2 = 47 (integer div).
    
    Rect rootRect = Rect(0, 0, 200, 100);
    Layout balanced = l.balance(cfg, rootRect);
    
    assert(balanced.type == Layout.Type.Node);
    assert(balanced.position == 65);
    assert(balanced.child2.type == Layout.Type.Node);
    assert(balanced.child2.position == 47);
}
