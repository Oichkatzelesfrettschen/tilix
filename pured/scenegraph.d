/**
 * Scene graph for tab/split layout.
 *
 * Represents a binary split tree and computes viewports for each pane.
 */
module pured.scenegraph;

version (PURE_D_BACKEND):

import pured.config : SplitLayoutConfig, SplitLayoutNode;

enum SplitOrientation {
    horizontal,
    vertical,
}

struct Viewport {
    int x;
    int y;
    int width;
    int height;
    int paneId;
}

class SceneNode {
public:
    bool isLeaf = true;
    int paneId;
    SplitOrientation orientation = SplitOrientation.horizontal;
    float splitRatio = 0.5f;
    SceneNode first;
    SceneNode second;

    this(int paneId) {
        this.paneId = paneId;
    }
}

class SceneGraph {
private:
    SceneNode _root;
    int _nextPaneId = 1;

public:
    this() {
        _root = new SceneNode(0);
    }

    this(int rootPaneId) {
        _root = new SceneNode(rootPaneId);
        _nextPaneId = rootPaneId + 1;
    }

    @property SceneNode root() {
        return _root;
    }

    @property int nextPaneId() const {
        return _nextPaneId;
    }

    @property void nextPaneId(int value) {
        if (value > _nextPaneId) {
            _nextPaneId = value;
        }
    }

    int splitLeaf(int paneId, SplitOrientation orientation, float ratio = 0.5f) {
        auto node = findLeaf(_root, paneId);
        if (node is null) {
            return -1;
        }
        int originalPaneId = node.paneId;
        int internalId = _nextPaneId++;
        int newPaneId = _nextPaneId++;

        node.isLeaf = false;
        node.paneId = internalId;
        node.orientation = orientation;
        node.splitRatio = clampRatio(ratio);
        node.first = new SceneNode(originalPaneId);
        node.second = new SceneNode(newPaneId);
        return newPaneId;
    }

    int splitLeafWithIds(int paneId, SplitOrientation orientation, float ratio,
            int internalId, int newPaneId) {
        auto node = findLeaf(_root, paneId);
        if (node is null) {
            return -1;
        }
        int originalPaneId = node.paneId;
        node.isLeaf = false;
        node.paneId = internalId;
        node.orientation = orientation;
        node.splitRatio = clampRatio(ratio);
        node.first = new SceneNode(originalPaneId);
        node.second = new SceneNode(newPaneId);

        int maxId = internalId > newPaneId ? internalId : newPaneId;
        if (_nextPaneId <= maxId) {
            _nextPaneId = maxId + 1;
        }
        return newPaneId;
    }

    bool adjustSplitForPane(int paneId, SplitOrientation orientation, float delta) {
        bool inFirst = false;
        auto node = findSplitForPane(_root, paneId, orientation, inFirst);
        if (node is null) {
            return false;
        }
        float signedDelta = inFirst ? delta : -delta;
        node.splitRatio = clampRatio(node.splitRatio + signedDelta);
        return true;
    }

    bool setSplitRatioForPane(int paneId, SplitOrientation orientation, float ratio) {
        bool inFirst = false;
        auto node = findSplitForPane(_root, paneId, orientation, inFirst);
        if (node is null) {
            return false;
        }
        node.splitRatio = clampRatio(ratio);
        return true;
    }

    SplitLayoutConfig toLayoutConfig() const {
        SplitLayoutConfig layout;
        if (_root is null) {
            return layout;
        }
        layout.rootPaneId = _root.paneId;
        appendLayout(_root, layout.nodes);
        return layout;
    }

    bool applyLayoutConfig(in SplitLayoutConfig layout) {
        if (layout.nodes.length == 0) {
            return false;
        }
        SceneNode[int] nodes;
        int maxPaneId = 0;
        foreach (nodeCfg; layout.nodes) {
            if (nodeCfg.paneId < 0) {
                continue;
            }
            if (nodeCfg.paneId > maxPaneId) {
                maxPaneId = nodeCfg.paneId;
            }
            if (nodeCfg.paneId in nodes) {
                continue;
            }
            nodes[nodeCfg.paneId] = new SceneNode(nodeCfg.paneId);
        }
        if (nodes.length == 0) {
            return false;
        }
        foreach (nodeCfg; layout.nodes) {
            if (!(nodeCfg.paneId in nodes)) {
                continue;
            }
            auto node = nodes[nodeCfg.paneId];
            bool hasChildren = nodeCfg.first >= 0 && nodeCfg.second >= 0;
            node.isLeaf = !hasChildren;
            if (hasChildren) {
                node.orientation = parseOrientation(nodeCfg.orientation);
                node.splitRatio = clampRatio(nodeCfg.splitRatio);
                if (nodeCfg.first in nodes) {
                    node.first = nodes[nodeCfg.first];
                }
                if (nodeCfg.second in nodes) {
                    node.second = nodes[nodeCfg.second];
                }
            }
        }

        int rootId = layout.rootPaneId;
        if (!(rootId in nodes)) {
            rootId = layout.nodes[0].paneId;
        }
        _root = nodes[rootId];
        _nextPaneId = maxPaneId + 1;
        return true;
    }

    void computeViewports(int x, int y, int width, int height,
            ref Viewport[] outViewports) {
        outViewports.length = 0;
        appendViewports(_root, x, y, width, height, outViewports);
    }

    bool hasPane(int paneId) {
        return containsPane(_root, paneId);
    }

private:
    SceneNode findLeaf(SceneNode node, int paneId) {
        if (node is null) {
            return null;
        }
        if (node.isLeaf) {
            return node.paneId == paneId ? node : null;
        }
        auto found = findLeaf(node.first, paneId);
        if (found !is null) {
            return found;
        }
        return findLeaf(node.second, paneId);
    }

    bool containsPane(SceneNode node, int paneId) {
        if (node is null) {
            return false;
        }
        if (node.isLeaf) {
            return node.paneId == paneId;
        }
        return containsPane(node.first, paneId) || containsPane(node.second, paneId);
    }

    SceneNode findSplitForPane(SceneNode node, int paneId,
            SplitOrientation orientation, out bool inFirst) {
        inFirst = false;
        if (node is null || node.isLeaf) {
            return null;
        }

        bool inLeft = containsPane(node.first, paneId);
        bool inRight = !inLeft && containsPane(node.second, paneId);
        if (!inLeft && !inRight) {
            return null;
        }

        SceneNode child = inLeft ? node.first : node.second;
        bool childInFirst;
        auto found = findSplitForPane(child, paneId, orientation, childInFirst);
        if (found !is null) {
            inFirst = childInFirst;
            return found;
        }

        if (node.orientation == orientation) {
            inFirst = inLeft;
            return node;
        }

        return null;
    }

    void appendViewports(SceneNode node, int x, int y, int width, int height,
            ref Viewport[] outViewports) {
        if (node is null) {
            return;
        }
        if (node.isLeaf) {
            outViewports ~= Viewport(x, y, width, height, node.paneId);
            return;
        }

        float ratio = clampRatio(node.splitRatio);
        if (node.orientation == SplitOrientation.vertical) {
            int wA = cast(int)(width * ratio);
            int wB = width - wA;
            appendViewports(node.first, x, y, wA, height, outViewports);
            appendViewports(node.second, x + wA, y, wB, height, outViewports);
        } else {
            int hA = cast(int)(height * ratio);
            int hB = height - hA;
            appendViewports(node.first, x, y, width, hA, outViewports);
            appendViewports(node.second, x, y + hA, width, hB, outViewports);
        }
    }

    float clampRatio(float ratio) {
        if (ratio < 0.1f) return 0.1f;
        if (ratio > 0.9f) return 0.9f;
        return ratio;
    }

    SplitOrientation parseOrientation(string value) {
        if (value == "vertical") {
            return SplitOrientation.vertical;
        }
        return SplitOrientation.horizontal;
    }

    string orientationLabel(SplitOrientation orientation) const {
        return orientation == SplitOrientation.vertical ? "vertical" : "horizontal";
    }

    void appendLayout(const SceneNode node, ref SplitLayoutNode[] nodes) const {
        if (node is null) {
            return;
        }
        SplitLayoutNode config;
        config.paneId = node.paneId;
        if (!node.isLeaf) {
            config.first = node.first is null ? -1 : node.first.paneId;
            config.second = node.second is null ? -1 : node.second.paneId;
            config.orientation = orientationLabel(node.orientation);
            config.splitRatio = node.splitRatio;
        } else {
            config.first = -1;
            config.second = -1;
            config.orientation = "";
            config.splitRatio = node.splitRatio;
        }
        nodes ~= config;
        if (!node.isLeaf) {
            appendLayout(node.first, nodes);
            appendLayout(node.second, nodes);
        }
    }
}

version (PURE_D_BACKEND) unittest {
    SceneGraph scene = new SceneGraph();
    Viewport[] viewports;
    scene.computeViewports(0, 0, 100, 50, viewports);
    assert(viewports.length == 1);
    assert(viewports[0].width == 100);
    assert(viewports[0].height == 50);

    auto newPane = scene.splitLeaf(0, SplitOrientation.vertical, 0.5f);
    assert(newPane != -1);
    scene.computeViewports(0, 0, 100, 50, viewports);
    assert(viewports.length == 2);
    assert(viewports[0].width + viewports[1].width == 100);
}
