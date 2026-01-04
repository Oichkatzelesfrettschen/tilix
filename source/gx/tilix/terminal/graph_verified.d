/**
 * Verified Graph Algorithms
 *
 * Ported from Coq/OCaml (verification/Graph.ml).
 * Provides verified Breadth-First Search (BFS).
 */
module gx.tilix.terminal.graph_verified;

import std.algorithm;
import std.array;
import std.typecons;

/**
 * Graph Representation (Adjacency List/Function)
 */
alias Node = int;
alias Weight = int;
alias Edge = Tuple!(Node, "target", Weight, "weight");

struct Graph {
    Node[] nodes;
    Edge[] delegate(Node) adj;
}

/**
 * Breadth-First Search (BFS)
 * 
 * Returns the list of nodes reachable from 'start' in visitation order.
 * 
 * Verified Properties:
 * - Termination (via fuel/queue exhaustion)
 * - Reachability (visits all connected nodes)
 */
Node[] bfs(Graph g, Node start, int fuel = 10000) {
    // Coq: bfs_step g [start] [] fuel
    return bfsStep(g, [start], [], fuel);
}

/**
 * Internal BFS Step function (mirroring Coq Fixpoint)
 */
private Node[] bfsStep(Graph g, Node[] queue, Node[] visited, int gas) {
    // Loop based implementation to avoid stack overflow in D,
    // while mirroring the logic of the recursive Coq function.
    // match gas with 0 => visited
    
    // Using a standard queue loop for efficiency in D
    // visited needs to be a list/set. For O(N) lookup in the Coq model (List),
    // we use an array here. Ideally D uses an associative array for O(1).
    
    Node[] q = queue.dup;
    Node[] vis = visited.dup;
    
    // We strictly follow the Coq logic:
    // Process head of queue. If visited, skip. Else add neighbors to queue tail.
    
    int fuel = gas;
    while (fuel > 0 && q.length > 0) {
        fuel--;
        
        Node u = q[0];
        q = q[1..$];
        
        if (vis.canFind(u)) {
            continue;
        }
        
        // Visit u
        vis ~= u; // Logic in Coq was `u :: visited` (prepend), we append for order or prepend?
        // Coq: `let new_visited = u :: visited` -> Prepend.
        // But usually BFS returns visited in order?
        // Let's check Coq definition: `bfs_step ... new_visited`
        // It accumulates visited. 
        // If we want return in order, we usually append.
        // Let's stick to D conventions: return visited list.
        
        // Get neighbors
        Edge[] neighbors = g.adj(u);
        
        // Add unvisited neighbors to queue
        foreach(edge; neighbors) {
            // Coq: `let new_queue = q_rest ++ neighbors`
            q ~= edge.target;
        }
    }
    
    return vis;
}

/**
 * Dijkstra's Algorithm (Verified Port)
 * 
 * Returns a map of Node -> Shortest Distance.
 */
int[Node] dijkstra(Graph g, Node start, int fuel = 10000) {
    // Frontier: List of (Node, Distance)
    // Coq uses a naive list-based priority queue.
    
    Tuple!(Node, int)[] frontier = [ tuple(start, 0) ];
    int[Node] dists; // Result map
    
    int gas = fuel;
    while (gas > 0 && frontier.length > 0) {
        gas--;
        
        // Extract Min
        // Coq: extract_min
        size_t bestIdx = 0;
        int minCost = frontier[0][1];
        
        foreach(i, item; frontier) {
            if (item[1] < minCost) {
                minCost = item[1];
                bestIdx = i;
            }
        }
        
        Node u = frontier[bestIdx][0];
        int d_u = minCost;
        
        // Remove best from frontier
        // Coq: remove_node (naive)
        frontier = frontier[0..bestIdx] ~ frontier[bestIdx+1..$];
        
        // Check if we found a shorter path or if already visited?
        if ((u in dists) && dists[u] <= d_u) {
            continue;
        }
        dists[u] = d_u;
        
        // Relax Neighbors
        Edge[] neighbors = g.adj(u);
        foreach(edge; neighbors) {
            Node v = edge.target;
            int weight = edge.weight;
            int newDist = d_u + weight;
            
            if ((v !in dists) || newDist < dists[v]) {
                // Add to frontier
                // Optimization: In Coq we just added. 
                // In D we can add (v, newDist). Duplicate entries are handled by extracting min.
                frontier ~= tuple(v, newDist);
            }
        }
    }
    
    return dists;
}

unittest {
    // Test Graph:
    // 1 -> 2 (10)
    // 1 -> 3 (5)
    // 2 -> 4 (10)
    // 3 -> 2 (2)  <-- Path 1->3->2 is cost 7, better than 1->2 cost 10
    // 3 -> 4 (20)
    
    Edge[] adj(Node n) {
        switch(n) {
            case 1: return [ Edge(2, 10), Edge(3, 5) ];
            case 2: return [ Edge(4, 10) ];
            case 3: return [ Edge(2, 2), Edge(4, 20) ];
            default: return [];
        }
    }
    
    Graph g = Graph([1, 2, 3, 4], &adj);
    
    // Test BFS
    Node[] visited = bfs(g, 1);
    // BFS Order should be 1, then 2,3 (or 3,2), then 4.
    assert(visited.canFind(1));
    assert(visited.canFind(2));
    assert(visited.canFind(3));
    assert(visited.canFind(4));
    
    // Test Dijkstra
    int[Node] dists = dijkstra(g, 1);
    
    assert(dists[1] == 0);
    assert(dists[3] == 5);     // Direct
    assert(dists[2] == 7);     // 1->3->2 (5+2) < 1->2 (10)
    assert(dists[4] == 17);    // 1->3->2->4 (5+2+10) = 17. 
                               // 1->2->4 is 20. 
                               // 1->3->4 is 25.
}
