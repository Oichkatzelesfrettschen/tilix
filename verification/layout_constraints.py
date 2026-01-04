# Z3 Layout Constraint Model for Tilix
# Requires: pip install z3-solver

from z3 import *

def solve_layout_resize(total_width, num_panes, min_width, current_widths, resize_target_idx, resize_delta):
    """
    Models a horizontal split resizing operation.
    
    Args:
        total_width: Total available width (pixels/chars)
        num_panes: Number of panes in the split
        min_width: Minimum width for any pane
        current_widths: List of current widths [w1, w2, ...]
        resize_target_idx: The index of the pane being resized (the drag handle is after this pane)
        resize_delta: How much to move the handle (positive = grow right, negative = grow left)
    """
    
    solver = Optimize()
    
    # Variables: New widths for each pane
    new_widths = [Int(f'w_{i}') for i in range(num_panes)]
    
    # Constraint 1: Conservation of Space
    solver.add(Sum(new_widths) == total_width)
    
    # Constraint 2: Minimum Size
    for w in new_widths:
        solver.add(w >= min_width)
        
    # Constraint 3: The Resizing Action
    # The drag handle between index `i` and `i+1` moves by `delta`.
    # This implies the sum of widths up to `i` changes by `delta`.
    # Sum(new_0..i) == Sum(old_0..i) + delta
    
    current_prefix_sum = sum(current_widths[:resize_target_idx+1])
    new_prefix_sum = Sum(new_widths[:resize_target_idx+1])
    
    # We treat the resize request as a "soft" constraint or a target
    # Ideally, we want exact match. If impossible (due to min_width), we minimize error.
    
    target_prefix_sum = current_prefix_sum + resize_delta
    abs_diff = Int('abs_diff')
    solver.add(abs_diff >= new_prefix_sum - target_prefix_sum)
    solver.add(abs_diff >= target_prefix_sum - new_prefix_sum)
    
    # Objective: Minimize deviation from the user's resize target
    solver.minimize(abs_diff)
    
    # Secondary Objective: Keep other panes as stable as possible
    # (Minimize changes to panes not adjacent to the handle if we had a multi-pane resize logic)
    
    if solver.check() == sat:
        model = solver.model()
        result = [model.eval(w).as_long() for w in new_widths]
        return result
    else:
        return None

if __name__ == "__main__":
    # Test Case: 3 Panes, Total 100, Min 10
    # Current: [33, 33, 34]
    # User drags handle 0 (between pane 0 and 1) by +50.
    # Expected: Pane 0 wants to be 83. Pane 1+2 must share 17.
    # Pane 1 min=10, Pane 2 min=10. Total needed 20. 
    # Available 17. Impossible? Z3 should find the closest valid configuration.
    
    print("Test 1: Aggressive Resize")
    res = solve_layout_resize(100, 3, 10, [33, 33, 34], 0, 50)
    print(f"Result: {res}") 
    # Expect: [80, 10, 10] (Pane 0 caps at 80 because 1&2 need 10 each)
