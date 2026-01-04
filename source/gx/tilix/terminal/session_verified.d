/**
 * Verified Session State Machine
 *
 * This module implements the Session logic mirroring the TLA+ specification.
 * File: verification/Session.tla
 *
 * It acts as a controller for the layout and processes, ensuring
 * that the state remains valid during transitions.
 */
module gx.tilix.terminal.session_verified;

import std.algorithm;
import std.array;
import std.exception;

/**
 * State Machine Definitions
 */
class SessionStateMachine {
    // TLA+: VARIABLES processes, layout, focus
    private int[] processes; // Process IDs (simulated)
    private int[] layout;    // Window IDs in layout
    private int focus;       // Current focused ID (0 = none)

    private int maxProcesses;

    this(int maxProc = 10) {
        this.maxProcesses = maxProc;
        this.focus = 0;
    }

    // TLA+: Invariants
    bool checkInvariants() {
        // TypeOK (implicit in D types, but checks bounds)
        if (processes.length > maxProcesses) return false;
        
        // LayoutBackedByProcess: layout \subseteq processes
        // REMOVED: In Tilix, a window can exist after the process dies ("Ghost Window" showing exit status)
        // So this invariant is too strong for the 'Crash' state.
        /*
        foreach(id; layout) {
            if (!processes.canFind(id)) return false;
        }
        */

        // FocusValid
        if (layout.length > 0 && focus != 0) {
            if (!layout.canFind(focus)) return false;
        }
        
        return true;
    }

    // TLA+: Action Spawn(id)
    void spawn(int id) {
        enforce(!processes.canFind(id), "Process already exists");
        enforce(processes.length < maxProcesses, "Max processes reached");

        processes ~= id;
        layout ~= id; // In this simple model, spawn always adds to layout
        
        if (focus == 0) {
            focus = id;
        }
        
        assert(checkInvariants());
    }

    // TLA+: Action ProcessExit(id)
    void processExit(int id) {
        // TLA+: processes' = processes \ {id}
        // TLA+: layout' = layout (Layout remains until UI cleans it)
        
        processes = processes.filter!(x => x != id).array;
        
        // Note: focus remains unchanged in TLA+ spec for this action
        // Use reconcile() to clean up layout and focus.
        
        assert(checkInvariants());
    }

    // TLA+: Action CloseWindow(id)
    void closeWindow(int id) {
        // TLA+: layout' = layout \ {id}
        // TLA+: processes' = processes \ {id} (Assuming close kills process)
        
        layout = layout.filter!(x => x != id).array;
        processes = processes.filter!(x => x != id).array;
        
        if (focus == id) {
            if (layout.length == 0) {
                focus = 0;
            } else {
                // TLA+: CHOOSE x \in layout
                focus = layout[0];
            }
        }
        
        assert(checkInvariants());
    }

    // TLA+: Action Reconcile
    void reconcile() {
        // Remove windows that have no process
        int[] newLayout;
        foreach(winId; layout) {
            if (processes.canFind(winId)) {
                newLayout ~= winId;
            }
        }
        layout = newLayout;
        
        if (focus != 0 && !layout.canFind(focus)) {
            focus = (layout.length > 0) ? layout[0] : 0;
        }
        
        assert(checkInvariants());
    }
    
    // Getters for testing
    int[] getProcesses() { return processes.dup; }
    int[] getLayout() { return layout.dup; }
    int getFocus() { return focus; }
}

unittest {
    // Simulation of TLA+ Trace
    auto sm = new SessionStateMachine(5);
    
    // Init
    assert(sm.getProcesses().length == 0);
    
    // Spawn(1)
    sm.spawn(1);
    assert(sm.getLayout() == [1]);
    assert(sm.getFocus() == 1);
    
    // Spawn(2)
    sm.spawn(2);
    assert(sm.getLayout() == [1, 2]);
    assert(sm.getFocus() == 1); // Focus shouldn't change automatically in this spec
    
    // ProcessExit(1) -> Crash
    sm.processExit(1);
    assert(sm.getProcesses() == [2]);
    assert(sm.getLayout() == [1, 2]); // Layout ghost remains
    
    // Reconcile
    sm.reconcile();
    assert(sm.getLayout() == [2]); // Ghost removed
    assert(sm.getFocus() == 2); // Focus shifted
    
    // CloseWindow(2)
    sm.closeWindow(2);
    assert(sm.getLayout().length == 0);
    assert(sm.getProcesses().length == 0);
    assert(sm.getFocus() == 0);
}
