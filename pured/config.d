module pured.config;

version (PURE_D_BACKEND):

import mir.deser.json : deserializeJson;
import std.file : exists, readText;
import std.path : buildPath, expandTilde;
import std.process : environment;
import std.stdio : stderr;
import std.string : toLower;

struct ThemeConfig {
    float[] foreground;
    float[] background;
    float[][] palette;
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
}

PureDConfig defaultConfig() {
    PureDConfig cfg;
    cfg.fontSize = 16;
    cfg.windowWidth = 1280;
    cfg.windowHeight = 720;
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
        auto parsed = text.deserializeJson!PureDConfig;
        return sanitizeConfig(parsed);
    } catch (Exception ex) {
        stderr.writefln("Warning: Failed to parse Pure D config at %s: %s",
            target, ex.msg);
    }
    return cfg;
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
