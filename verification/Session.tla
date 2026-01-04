--------------------------- MODULE Session ---------------------------
EXTENDS Integers, Sequences, FiniteSets

CONSTANTS 
    MaxProcesses * Maximum number of processes allowed

VARIABLES 
    processes,      * Set of running process IDs
    layout,         * Set of window IDs currently in the layout
    focus           * The ID of the currently focused window

vars == <<processes, layout, focus>>

* Initial State
Init == 
    /\ processes = {}
    /\ layout = {}
    /\ focus = 0  * 0 represents "No Focus"

* Invariants
TypeOK == 
    /\ processes \subseteq 1..MaxProcesses
    /\ layout \subseteq 1..MaxProcesses
    /\ focus \in (layout \union {0})

* Safety: Every window in the layout must have a backing process
* DEPRECATED: Tilix allows "Ghost Windows" (process dead, window open showing exit code)
* LayoutBackedByProcess == 
*    layout \subseteq processes

* Safety: Focus must be valid
FocusValid == 
    (layout # {}) => (focus \in layout)

* Actions

* Spawn a new terminal
Spawn(id) == 
    /\ id \notin processes
    /\ Cardinality(processes) < MaxProcesses
    /\ processes' = processes \union {id}
    /\ layout' = layout \union {id}
    /\ (focus = 0) => (focus' = id)
    /\ (focus # 0) => (focus' = focus)

* Process crashes or exits
ProcessExit(id) == 
    /\ id \in processes
    /\ processes' = processes \ {id}
    /\ layout' = layout  * Note: Layout might still hold the window until UI cleans it up!
    /\ UNCHANGED <<focus>>

* User closes a window
CloseWindow(id) == 
    /\ id \in layout
    /\ layout' = layout \ {id}
    /\ processes' = processes \ {id} * Assume closing window kills process
    /\ IF focus = id 
       THEN IF layout' = {} THEN focus' = 0 ELSE focus' = CHOOSE x \in layout' : TRUE 
       ELSE focus' = focus

* Reconcile Layout (The "Garbage Collector" action)
Reconcile == 
    /\ \E id \in layout : id \notin processes
    /\ layout' = layout \ {id \in layout : id \notin processes}
    /\ UNCHANGED <<processes, focus>>

* Next State Relation
Next == 
    /\ \E id \in 1..MaxProcesses : Spawn(id)
    /\ \E id \in processes : ProcessExit(id)
    /\ \E id \in layout : CloseWindow(id)
    /\ Reconcile

* Specification
Spec == Init /\ [][Next]_vars

=============================================================================
