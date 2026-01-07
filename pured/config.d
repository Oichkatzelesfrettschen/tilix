module pured.config;

version (PURE_D_BACKEND):

import mir.deser.json : deserializeJson;
import std.file : exists, readText, write, mkdirRecurse;
import std.json : JSONValue, JSONType, parseJSON;
import std.path : buildPath, expandTilde, dirName;
import std.process : environment;
import std.stdio : stderr;
import std.string : toLower;

struct ThemeConfig {
    float[] foreground;
    float[] background;
    float[][] palette;
}

struct SplitLayoutNode {
    int paneId = -1;
    int first = -1;
    int second = -1;
    string orientation;
    float splitRatio = 0.5f;
}

struct SplitLayoutConfig {
    int rootPaneId = 0;
    int activePaneId = 0;
    SplitLayoutNode[] nodes;
}

struct ResolvedTheme {
    float[4] foreground;
    float[4] background;
    float[4][16] palette;
}

struct PureDConfig {
    string fontPath;
    int fontSize;
    int windowWidth;
    int windowHeight;
    bool quakeMode;
    float quakeHeight;
    size_t scrollbackMaxLines;
    int swapInterval;
    string themePath;
    string themeFormat;
    string cursorStyle;
    float cursorThickness;
    string accessibilityPreset;
    float[] selectionBg;
    float[] selectionFg;
    float[] searchBg;
    float[] searchFg;
    float[] linkFg;
    ThemeConfig theme;
    SplitLayoutConfig splitLayout;
}

PureDConfig defaultConfig() {
    PureDConfig cfg;
    cfg.fontSize = 16;
    cfg.windowWidth = 1280;
    cfg.windowHeight = 720;
    cfg.quakeMode = false;
    cfg.quakeHeight = 0.4f;
    cfg.scrollbackMaxLines = 200_000;
    cfg.swapInterval = 0;
    cfg.themePath = "";
    cfg.themeFormat = "";
    cfg.cursorStyle = "";
    cfg.cursorThickness = 0.0f;
    cfg.accessibilityPreset = "";
    cfg.selectionBg = [0.2f, 0.6f, 0.8f, 1.0f];
    cfg.selectionFg = [];
    cfg.searchBg = [0.85f, 0.7f, 0.2f, 1.0f];
    cfg.searchFg = [];
    cfg.linkFg = [0.2f, 0.6f, 1.0f, 1.0f];
    cfg.splitLayout = SplitLayoutConfig.init;
    return cfg;
}

const(ResolvedTheme)* defaultResolvedTheme() @nogc nothrow {
    static immutable ResolvedTheme theme = initDefaultTheme();
    return &theme;
}

ResolvedTheme resolveTheme(in ThemeConfig theme) {
    ResolvedTheme resolved = *defaultResolvedTheme();
    if (theme.foreground.length == 4) {
        resolved.foreground = [theme.foreground[0], theme.foreground[1],
            theme.foreground[2], theme.foreground[3]];
    }
    if (theme.background.length == 4) {
        resolved.background = [theme.background[0], theme.background[1],
            theme.background[2], theme.background[3]];
    }
    if (theme.palette.length >= 16) {
        foreach (idx; 0 .. 16) {
            if (theme.palette[idx].length == 4) {
                resolved.palette[idx] = [theme.palette[idx][0],
                    theme.palette[idx][1],
                    theme.palette[idx][2],
                    theme.palette[idx][3]];
            }
        }
    }
    return resolved;
}

PureDConfig sanitizeConfig(PureDConfig cfg) {
    auto def = defaultConfig();
    applyAccessibilityPreset(cfg);
    if (cfg.fontSize <= 0) {
        cfg.fontSize = def.fontSize;
    }
    if (cfg.windowWidth <= 0) {
        cfg.windowWidth = def.windowWidth;
    }
    if (cfg.windowHeight <= 0) {
        cfg.windowHeight = def.windowHeight;
    }
    if (cfg.quakeHeight <= 0.0f || cfg.quakeHeight > 1.0f) {
        cfg.quakeHeight = def.quakeHeight;
    }
    if (cfg.scrollbackMaxLines < 1_000) {
        cfg.scrollbackMaxLines = def.scrollbackMaxLines;
    }
    if (cfg.swapInterval < 0) {
        cfg.swapInterval = def.swapInterval;
    }
    if (cfg.cursorThickness < 0.0f) {
        cfg.cursorThickness = def.cursorThickness;
    }
    if (cfg.selectionBg.length != 4) {
        cfg.selectionBg = def.selectionBg;
    } else {
        foreach (i; 0 .. 4) {
            cfg.selectionBg[i] = clamp01(cfg.selectionBg[i]);
        }
    }
    if (cfg.selectionFg.length == 4) {
        foreach (i; 0 .. 4) {
            cfg.selectionFg[i] = clamp01(cfg.selectionFg[i]);
        }
    } else {
        cfg.selectionFg = [];
    }
    if (cfg.searchBg.length != 4) {
        cfg.searchBg = def.searchBg;
    } else {
        foreach (i; 0 .. 4) {
            cfg.searchBg[i] = clamp01(cfg.searchBg[i]);
        }
    }
    if (cfg.searchFg.length == 4) {
        foreach (i; 0 .. 4) {
            cfg.searchFg[i] = clamp01(cfg.searchFg[i]);
        }
    } else {
        cfg.searchFg = [];
    }
    if (cfg.linkFg.length == 4) {
        foreach (i; 0 .. 4) {
            cfg.linkFg[i] = clamp01(cfg.linkFg[i]);
        }
    } else {
        cfg.linkFg = def.linkFg;
    }
    cfg.splitLayout = sanitizeSplitLayout(cfg.splitLayout);
    return cfg;
}

private void applyAccessibilityPreset(ref PureDConfig cfg) {
    if (cfg.accessibilityPreset.length == 0) {
        return;
    }
    auto preset = toLower(cfg.accessibilityPreset);
    if (preset == "high-contrast") {
        if (cfg.cursorStyle.length == 0) {
            cfg.cursorStyle = "outline";
        }
        if (cfg.cursorThickness <= 0.0f) {
            cfg.cursorThickness = 2.0f;
        }
        if (cfg.selectionBg.length != 4) {
            cfg.selectionBg = [1.0f, 0.84f, 0.0f, 1.0f]; // gold
        }
        if (cfg.searchBg.length != 4) {
            cfg.searchBg = [1.0f, 0.0f, 1.0f, 1.0f]; // magenta
        }
        if (cfg.linkFg.length != 4) {
            cfg.linkFg = [0.0f, 0.78f, 1.0f, 1.0f]; // cyan
        }
    } else if (preset == "low-vision") {
        if (cfg.cursorStyle.length == 0) {
            cfg.cursorStyle = "outline";
        }
        if (cfg.cursorThickness <= 0.0f) {
            cfg.cursorThickness = 3.0f;
        }
        if (cfg.selectionBg.length != 4) {
            cfg.selectionBg = [0.0f, 0.75f, 0.75f, 1.0f]; // bright cyan
        }
        if (cfg.searchBg.length != 4) {
            cfg.searchBg = [1.0f, 0.5f, 0.0f, 1.0f]; // orange
        }
        if (cfg.linkFg.length != 4) {
            cfg.linkFg = [1.0f, 0.82f, 0.0f, 1.0f]; // yellow
        }
    }
}

string defaultConfigPath() {
    string base = environment.get("XDG_CONFIG_HOME", "");
    if (base.length == 0) {
        base = expandTilde("~/.config");
    }
    return buildPath(base, "tilix", "pure-d.json");
}

PureDConfig loadConfig(string path = null) {
    auto cfg = defaultConfig();
    string target = (path is null || path.length == 0) ? defaultConfigPath() : path;
    if (!exists(target)) {
        return cfg;
    }
    try {
        auto text = readText(target);
        try {
            auto root = parseJSON(text);
            warnUnknownKeys(root, target);
        } catch (Exception ex) {
            stderr.writefln("Warning: Failed to parse Pure D config at %s: %s",
                target, ex.msg);
            return cfg;
        }
        auto parsed = text.deserializeJson!PureDConfig;
        return sanitizeConfig(parsed);
    } catch (Exception ex) {
        stderr.writefln("Warning: Failed to parse Pure D config at %s: %s",
            target, ex.msg);
    }
    return cfg;
}

private void warnUnknownKeys(JSONValue root, string path) {
    if (root.type != JSONType.object) {
        return;
    }
    bool[string] allowed = [
        "fontPath": true,
        "fontSize": true,
        "windowWidth": true,
        "windowHeight": true,
        "quakeMode": true,
        "quakeHeight": true,
        "scrollbackMaxLines": true,
        "swapInterval": true,
        "themePath": true,
        "themeFormat": true,
        "cursorStyle": true,
        "cursorThickness": true,
        "accessibilityPreset": true,
        "selectionBg": true,
        "selectionFg": true,
        "searchBg": true,
        "searchFg": true,
        "linkFg": true,
        "theme": true,
        "splitLayout": true,
    ];
    auto rootObj = root.object;
    foreach (key, _; rootObj) {
        if (!(key in allowed)) {
            stderr.writefln("Warning: Unknown config key in %s: %s", path, key);
        }
    }

    if ("theme" in rootObj) {
        auto themeVal = rootObj["theme"];
        if (themeVal.type == JSONType.object) {
            bool[string] themeAllowed = [
                "foreground": true,
                "background": true,
                "palette": true,
            ];
            foreach (key, _; themeVal.object) {
                if (!(key in themeAllowed)) {
                    stderr.writefln("Warning: Unknown theme key in %s: %s", path, key);
                }
            }
        }
    }

    if ("splitLayout" in rootObj) {
        auto splitVal = rootObj["splitLayout"];
        if (splitVal.type == JSONType.object) {
            bool[string] splitAllowed = [
                "rootPaneId": true,
                "activePaneId": true,
                "nodes": true,
            ];
            foreach (key, _; splitVal.object) {
                if (!(key in splitAllowed)) {
                    stderr.writefln("Warning: Unknown splitLayout key in %s: %s", path, key);
                }
            }
            if ("nodes" in splitVal.object) {
                auto nodesVal = splitVal.object["nodes"];
                if (nodesVal.type == JSONType.array) {
                    foreach (i, nodeVal; nodesVal.array) {
                        if (nodeVal.type != JSONType.object) {
                            stderr.writefln("Warning: splitLayout.nodes[%d] is not an object in %s", i, path);
                            continue;
                        }
                        bool[string] nodeAllowed = [
                            "paneId": true,
                            "first": true,
                            "second": true,
                            "orientation": true,
                            "splitRatio": true,
                        ];
                        foreach (key, _; nodeVal.object) {
                            if (!(key in nodeAllowed)) {
                                stderr.writefln(
                                    "Warning: Unknown splitLayout.nodes[%d] key in %s: %s",
                                    i, path, key);
                            }
                        }
                    }
                }
            }
        }
    }
}

SplitLayoutConfig sanitizeSplitLayout(SplitLayoutConfig layout) {
    if (layout.nodes.length == 0) {
        layout.rootPaneId = 0;
        layout.activePaneId = 0;
        return layout;
    }
    bool hasRoot = false;
    bool hasActive = false;
    bool[int] isLeaf;
    foreach (ref node; layout.nodes) {
        if (node.paneId == layout.rootPaneId) {
            hasRoot = true;
        }
        if (node.paneId == layout.activePaneId) {
            hasActive = true;
        }
        node.splitRatio = clampRatio(node.splitRatio);
        node.orientation = sanitizeOrientation(node.orientation);
        if (node.paneId >= 0) {
            isLeaf[node.paneId] = node.first < 0 || node.second < 0;
        }
    }
    if (!hasRoot) {
        layout.rootPaneId = layout.nodes[0].paneId;
    }
    if (!hasActive || !(layout.activePaneId in isLeaf) || !isLeaf[layout.activePaneId]) {
        int fallback = -1;
        foreach (node; layout.nodes) {
            if (node.paneId in isLeaf && isLeaf[node.paneId]) {
                fallback = node.paneId;
                break;
            }
        }
        if (fallback < 0) {
            fallback = layout.rootPaneId;
        }
        layout.activePaneId = fallback;
    }
    return layout;
}

bool saveSplitLayout(in SplitLayoutConfig layout, string path = null) {
    string target = (path is null || path.length == 0)
        ? defaultConfigPath()
        : path;

    JSONValue root;
    if (exists(target)) {
        try {
            root = parseJSON(readText(target));
        } catch (Exception ex) {
            stderr.writefln("Warning: Failed to parse config for layout save at %s: %s",
                target, ex.msg);
            return false;
        }
    }

    if (root.type != JSONType.object) {
        root = ["splitLayout": buildLayoutJson(layout)];
    } else {
        root["splitLayout"] = buildLayoutJson(layout);
    }

    auto parentDir = dirName(target);
    if (parentDir.length > 0 && !exists(parentDir)) {
        mkdirRecurse(parentDir);
    }
    write(target, root.toString());
    return true;
}

private JSONValue buildLayoutJson(in SplitLayoutConfig layout) {
    JSONValue[] nodes;
    nodes.length = layout.nodes.length;
    foreach (i, node; layout.nodes) {
        JSONValue[string] entry;
        entry["paneId"] = node.paneId;
        entry["first"] = node.first;
        entry["second"] = node.second;
        entry["orientation"] = node.orientation;
        entry["splitRatio"] = node.splitRatio;
        nodes[i] = entry;
    }
    JSONValue[string] root;
    root["rootPaneId"] = layout.rootPaneId;
    root["activePaneId"] = layout.activePaneId;
    root["nodes"] = nodes;
    return JSONValue(root);
}

private string sanitizeOrientation(string value) {
    auto lowered = toLower(value);
    if (lowered == "horizontal" || lowered == "vertical") {
        return lowered;
    }
    return "";
}

private float clampRatio(float value) {
    if (value < 0.1f) {
        return 0.1f;
    }
    if (value > 0.9f) {
        return 0.9f;
    }
    return value;
}

private float clamp01(float value) {
    if (value < 0.0f) {
        return 0.0f;
    }
    if (value > 1.0f) {
        return 1.0f;
    }
    return value;
}

private ResolvedTheme initDefaultTheme() @nogc nothrow {
    ResolvedTheme theme;
    theme.foreground = [0.9f, 0.9f, 0.9f, 1.0f];
    theme.background = [0.1f, 0.1f, 0.15f, 1.0f];
    theme.palette = defaultPalette;
    return theme;
}

private immutable float[4][16] defaultPalette = [
    [0.0f, 0.0f, 0.0f, 1.0f],       // 0: Black
    [0.8f, 0.0f, 0.0f, 1.0f],       // 1: Red
    [0.0f, 0.8f, 0.0f, 1.0f],       // 2: Green
    [0.8f, 0.8f, 0.0f, 1.0f],       // 3: Yellow
    [0.0f, 0.0f, 0.8f, 1.0f],       // 4: Blue
    [0.8f, 0.0f, 0.8f, 1.0f],       // 5: Magenta
    [0.0f, 0.8f, 0.8f, 1.0f],       // 6: Cyan
    [0.75f, 0.75f, 0.75f, 1.0f],    // 7: White
    [0.5f, 0.5f, 0.5f, 1.0f],       // 8: Bright Black
    [1.0f, 0.0f, 0.0f, 1.0f],       // 9: Bright Red
    [0.0f, 1.0f, 0.0f, 1.0f],       // 10: Bright Green
    [1.0f, 1.0f, 0.0f, 1.0f],       // 11: Bright Yellow
    [0.0f, 0.0f, 1.0f, 1.0f],       // 12: Bright Blue
    [1.0f, 0.0f, 1.0f, 1.0f],       // 13: Bright Magenta
    [0.0f, 1.0f, 1.0f, 1.0f],       // 14: Bright Cyan
    [1.0f, 1.0f, 1.0f, 1.0f],       // 15: Bright White
];
