/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.theme.palette;

import std.algorithm : startsWith, endsWith, find;
import std.array : split;
import std.conv : to, ConvException;
import std.experimental.logger;
import std.file : readText, exists, dirEntries, SpanMode, isFile;
import std.path : baseName, stripExtension;
import std.string : strip, toLower, indexOf;

import gdk.RGBA;

/**
 * Color scheme variant (light or dark mode).
 */
enum ColorScheme {
    Light,
    Dark
}

/**
 * Terminal color palette.
 *
 * Supports Ptyxis-compatible palette format with light/dark variants.
 * Contains 16 ANSI colors plus foreground/background and special indicators.
 */
struct Palette {
    string name;
    string id;  // Filesystem-safe identifier

    // Color arrays for light and dark modes
    RGBA[16][2] colors;  // [scheme][color index]
    RGBA[2] foreground;
    RGBA[2] background;

    // Special indicator colors (optional)
    RGBA[2] bellFg;
    RGBA[2] bellBg;
    RGBA[2] remoteFg;
    RGBA[2] remoteBg;
    RGBA[2] superuserFg;
    RGBA[2] superuserBg;
    bool hasBell;
    bool hasRemote;
    bool hasSuperuser;

    /**
     * Get colors for specified scheme.
     */
    RGBA[] getColors(ColorScheme scheme) {
        return colors[cast(size_t)scheme][];
    }

    /**
     * Get foreground for specified scheme.
     */
    RGBA getForeground(ColorScheme scheme) {
        return foreground[cast(size_t)scheme];
    }

    /**
     * Get background for specified scheme.
     */
    RGBA getBackground(ColorScheme scheme) {
        return background[cast(size_t)scheme];
    }

    /**
     * Check if palette is valid (has required colors).
     * Note: RGBA.alpha() is not const-compatible in gtk-d, so we check name only.
     */
    @property bool isValid() const {
        return name.length > 0;
    }

    /**
     * Non-const validation that checks color values.
     */
    bool validate() {
        return name.length > 0 &&
               foreground[0].alpha > 0 && foreground[1].alpha > 0 &&
               background[0].alpha > 0 && background[1].alpha > 0;
    }
}

/**
 * Parse a hex color string to RGBA.
 * Supports formats: #RGB, #RRGGBB, #RRGGBBAA
 */
RGBA parseHexColor(string hex) {
    RGBA rgba = new RGBA();
    rgba.alpha = 1.0;

    if (hex.length == 0 || hex[0] != '#') {
        return rgba;
    }

    hex = hex[1 .. $];  // Remove #

    try {
        if (hex.length == 3) {
            // #RGB -> #RRGGBB
            rgba.red = to!ubyte(hex[0 .. 1] ~ hex[0 .. 1], 16) / 255.0;
            rgba.green = to!ubyte(hex[1 .. 2] ~ hex[1 .. 2], 16) / 255.0;
            rgba.blue = to!ubyte(hex[2 .. 3] ~ hex[2 .. 3], 16) / 255.0;
        } else if (hex.length == 6) {
            // #RRGGBB
            rgba.red = to!ubyte(hex[0 .. 2], 16) / 255.0;
            rgba.green = to!ubyte(hex[2 .. 4], 16) / 255.0;
            rgba.blue = to!ubyte(hex[4 .. 6], 16) / 255.0;
        } else if (hex.length == 8) {
            // #RRGGBBAA
            rgba.red = to!ubyte(hex[0 .. 2], 16) / 255.0;
            rgba.green = to!ubyte(hex[2 .. 4], 16) / 255.0;
            rgba.blue = to!ubyte(hex[4 .. 6], 16) / 255.0;
            rgba.alpha = to!ubyte(hex[6 .. 8], 16) / 255.0;
        }
    } catch (ConvException e) {
        tracef("Invalid hex color: %s", hex);
    }

    return rgba;
}

/**
 * Convert RGBA to hex string.
 */
string toHexColor(RGBA rgba) {
    import std.format : format;
    return format("#%02X%02X%02X",
        cast(ubyte)(rgba.red * 255),
        cast(ubyte)(rgba.green * 255),
        cast(ubyte)(rgba.blue * 255));
}

/**
 * Parse a Ptyxis-style palette file.
 *
 * Format:
 * [Palette]
 * Name=Palette Name
 *
 * [Light]
 * Foreground=#RRGGBB
 * Background=#RRGGBB
 * Color0=#RRGGBB
 * ...
 * Color15=#RRGGBB
 *
 * [Dark]
 * Foreground=#RRGGBB
 * Background=#RRGGBB
 * Color0=#RRGGBB
 * ...
 * Color15=#RRGGBB
 */
Palette parsePaletteFile(string content, string defaultName = "Unknown") {
    Palette palette;
    palette.name = defaultName;

    enum Section { None, Palette, Light, Dark }
    Section currentSection = Section.None;

    foreach (line; content.split("\n")) {
        line = strip(line);

        // Skip empty lines and comments
        if (line.length == 0 || line[0] == '#' || line[0] == ';') {
            continue;
        }

        // Section header
        if (line[0] == '[' && line[$ - 1] == ']') {
            string sectionName = line[1 .. $ - 1].toLower;
            switch (sectionName) {
                case "palette": currentSection = Section.Palette; break;
                case "light": currentSection = Section.Light; break;
                case "dark": currentSection = Section.Dark; break;
                default: currentSection = Section.None; break;
            }
            continue;
        }

        // Key=Value pair
        auto eqIdx = line.indexOf('=');
        if (eqIdx < 0) continue;

        string key = strip(line[0 .. eqIdx]).toLower;
        string value = strip(line[eqIdx + 1 .. $]);

        // Parse based on section
        final switch (currentSection) {
            case Section.None:
                break;

            case Section.Palette:
                if (key == "name") {
                    palette.name = value;
                }
                break;

            case Section.Light:
                parsePaletteEntry(palette, ColorScheme.Light, key, value);
                break;

            case Section.Dark:
                parsePaletteEntry(palette, ColorScheme.Dark, key, value);
                break;
        }
    }

    // Generate ID from name
    palette.id = generatePaletteId(palette.name);

    return palette;
}

private void parsePaletteEntry(ref Palette palette, ColorScheme scheme, string key, string value) {
    size_t idx = cast(size_t)scheme;
    RGBA color = parseHexColor(value);

    switch (key) {
        case "foreground":
            palette.foreground[idx] = color;
            break;
        case "background":
            palette.background[idx] = color;
            break;
        case "bell":
            palette.bellFg[idx] = color;
            palette.bellBg[idx] = parseHexColor(value);  // Often same as fg
            palette.hasBell = true;
            break;
        case "bellforeground":
            palette.bellFg[idx] = color;
            palette.hasBell = true;
            break;
        case "bellbackground":
            palette.bellBg[idx] = color;
            palette.hasBell = true;
            break;
        case "remote":
        case "remoteforeground":
            palette.remoteFg[idx] = color;
            palette.hasRemote = true;
            break;
        case "remotebackground":
            palette.remoteBg[idx] = color;
            palette.hasRemote = true;
            break;
        case "superuser":
        case "superuserforeground":
            palette.superuserFg[idx] = color;
            palette.hasSuperuser = true;
            break;
        case "superuserbackground":
            palette.superuserBg[idx] = color;
            palette.hasSuperuser = true;
            break;
        default:
            // Check for Color0-Color15
            if (key.startsWith("color")) {
                try {
                    int colorIdx = to!int(key[5 .. $]);
                    if (colorIdx >= 0 && colorIdx < 16) {
                        palette.colors[idx][colorIdx] = color;
                    }
                } catch (ConvException e) {
                    // Ignore invalid color indices
                }
            }
            break;
    }
}

/**
 * Generate a filesystem-safe ID from palette name.
 */
string generatePaletteId(string name) {
    import std.uni : toLower, isAlphaNum;
    import std.array : appender;

    auto result = appender!string;
    foreach (c; name) {
        if (isAlphaNum(c)) {
            result ~= toLower(c);
        } else if (c == ' ' || c == '-' || c == '_') {
            result ~= '-';
        }
    }
    return result.data;
}

/**
 * Load a palette from file.
 */
Palette loadPalette(string filepath) {
    if (!exists(filepath)) {
        tracef("Palette file not found: %s", filepath);
        return Palette.init;
    }

    try {
        string content = readText(filepath);
        string name = baseName(filepath).stripExtension;
        return parsePaletteFile(content, name);
    } catch (Exception e) {
        tracef("Failed to load palette: %s - %s", filepath, e.msg);
        return Palette.init;
    }
}

/**
 * Load all palettes from a directory.
 */
Palette[] loadPalettesFromDirectory(string dirPath) {
    Palette[] palettes;

    if (!exists(dirPath)) {
        tracef("Palette directory not found: %s", dirPath);
        return palettes;
    }

    try {
        foreach (entry; dirEntries(dirPath, "*.palette", SpanMode.shallow)) {
            if (isFile(entry.name)) {
                auto palette = loadPalette(entry.name);
                if (palette.isValid) {
                    palettes ~= palette;
                }
            }
        }
    } catch (Exception e) {
        tracef("Failed to scan palette directory: %s - %s", dirPath, e.msg);
    }

    tracef("Loaded %d palettes from %s", palettes.length, dirPath);
    return palettes;
}

/**
 * Built-in palettes.
 */
Palette[] getBuiltinPalettes() {
    Palette[] palettes;

    // Tango palette (GNOME default)
    palettes ~= createTangoPalette();

    // Solarized Dark
    palettes ~= createSolarizedDarkPalette();

    // Solarized Light
    palettes ~= createSolarizedLightPalette();

    // Dracula
    palettes ~= createDraculaPalette();

    // Nord
    palettes ~= createNordPalette();

    return palettes;
}

private Palette createTangoPalette() {
    Palette p;
    p.name = "Tango";
    p.id = "tango";

    // Light mode
    p.foreground[0] = parseHexColor("#2e3436");
    p.background[0] = parseHexColor("#eeeeec");

    // Dark mode
    p.foreground[1] = parseHexColor("#d3d7cf");
    p.background[1] = parseHexColor("#2e3436");

    // Tango colors (same for both modes)
    string[16] tangoColors = [
        "#2e3436", "#cc0000", "#4e9a06", "#c4a000",
        "#3465a4", "#75507b", "#06989a", "#d3d7cf",
        "#555753", "#ef2929", "#8ae234", "#fce94f",
        "#729fcf", "#ad7fa8", "#34e2e2", "#eeeeec"
    ];

    foreach (i, hex; tangoColors) {
        RGBA color = parseHexColor(hex);
        p.colors[0][i] = color;
        p.colors[1][i] = color;
    }

    return p;
}

private Palette createSolarizedDarkPalette() {
    Palette p;
    p.name = "Solarized Dark";
    p.id = "solarized-dark";

    p.foreground[0] = parseHexColor("#839496");
    p.background[0] = parseHexColor("#002b36");
    p.foreground[1] = parseHexColor("#839496");
    p.background[1] = parseHexColor("#002b36");

    string[16] colors = [
        "#073642", "#dc322f", "#859900", "#b58900",
        "#268bd2", "#d33682", "#2aa198", "#eee8d5",
        "#002b36", "#cb4b16", "#586e75", "#657b83",
        "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"
    ];

    foreach (i, hex; colors) {
        RGBA color = parseHexColor(hex);
        p.colors[0][i] = color;
        p.colors[1][i] = color;
    }

    return p;
}

private Palette createSolarizedLightPalette() {
    Palette p;
    p.name = "Solarized Light";
    p.id = "solarized-light";

    p.foreground[0] = parseHexColor("#657b83");
    p.background[0] = parseHexColor("#fdf6e3");
    p.foreground[1] = parseHexColor("#657b83");
    p.background[1] = parseHexColor("#fdf6e3");

    string[16] colors = [
        "#073642", "#dc322f", "#859900", "#b58900",
        "#268bd2", "#d33682", "#2aa198", "#eee8d5",
        "#002b36", "#cb4b16", "#586e75", "#657b83",
        "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"
    ];

    foreach (i, hex; colors) {
        RGBA color = parseHexColor(hex);
        p.colors[0][i] = color;
        p.colors[1][i] = color;
    }

    return p;
}

private Palette createDraculaPalette() {
    Palette p;
    p.name = "Dracula";
    p.id = "dracula";

    p.foreground[0] = parseHexColor("#f8f8f2");
    p.background[0] = parseHexColor("#282a36");
    p.foreground[1] = parseHexColor("#f8f8f2");
    p.background[1] = parseHexColor("#282a36");

    string[16] colors = [
        "#21222c", "#ff5555", "#50fa7b", "#f1fa8c",
        "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
        "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5",
        "#d6acff", "#ff92df", "#a4ffff", "#ffffff"
    ];

    foreach (i, hex; colors) {
        RGBA color = parseHexColor(hex);
        p.colors[0][i] = color;
        p.colors[1][i] = color;
    }

    return p;
}

private Palette createNordPalette() {
    Palette p;
    p.name = "Nord";
    p.id = "nord";

    p.foreground[0] = parseHexColor("#d8dee9");
    p.background[0] = parseHexColor("#2e3440");
    p.foreground[1] = parseHexColor("#d8dee9");
    p.background[1] = parseHexColor("#2e3440");

    string[16] colors = [
        "#3b4252", "#bf616a", "#a3be8c", "#ebcb8b",
        "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
        "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b",
        "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"
    ];

    foreach (i, hex; colors) {
        RGBA color = parseHexColor(hex);
        p.colors[0][i] = color;
        p.colors[1][i] = color;
    }

    return p;
}

/**
 * Palette manager for loading and caching palettes.
 */
class PaletteManager {
private:
    Palette[] _palettes;
    Palette* _current;
    ColorScheme _scheme;

public:
    this() {
        // Load built-in palettes
        _palettes = getBuiltinPalettes();

        // Set default
        if (_palettes.length > 0) {
            _current = &_palettes[0];
        }

        _scheme = ColorScheme.Dark;  // Default to dark
    }

    /**
     * Load additional palettes from directory.
     */
    void loadFromDirectory(string dirPath) {
        _palettes ~= loadPalettesFromDirectory(dirPath);
    }

    /**
     * Get all available palettes.
     */
    @property const(Palette)[] palettes() const {
        return _palettes;
    }

    /**
     * Get current palette.
     */
    @property const(Palette)* current() const {
        return _current;
    }

    /**
     * Set current palette by ID.
     */
    bool setCurrent(string id) {
        foreach (ref p; _palettes) {
            if (p.id == id) {
                _current = &p;
                return true;
            }
        }
        return false;
    }

    /**
     * Get current color scheme.
     */
    @property ColorScheme scheme() const {
        return _scheme;
    }

    /**
     * Set color scheme.
     */
    @property void scheme(ColorScheme s) {
        _scheme = s;
    }

    /**
     * Get colors for current palette and scheme.
     */
    RGBA[] getCurrentColors() {
        if (_current is null) return null;
        return _current.getColors(_scheme);
    }

    /**
     * Get foreground for current palette and scheme.
     */
    RGBA getCurrentForeground() {
        if (_current is null) return new RGBA();
        return _current.getForeground(_scheme);
    }

    /**
     * Get background for current palette and scheme.
     */
    RGBA getCurrentBackground() {
        if (_current is null) return new RGBA();
        return _current.getBackground(_scheme);
    }

    /**
     * Find palette by name (case-insensitive).
     */
    Palette* findByName(string name) {
        string lowerName = name.toLower;
        foreach (ref p; _palettes) {
            if (p.name.toLower == lowerName || p.id == lowerName) {
                return &p;
            }
        }
        return null;
    }

    /**
     * Find palette by ID (exact match).
     */
    Palette* findById(string id) {
        foreach (ref p; _palettes) {
            if (p.id == id) {
                return &p;
            }
        }
        return null;
    }

    /**
     * Get all palettes (mutable access for iteration).
     */
    Palette[] getAllPalettes() {
        return _palettes;
    }
}

@system
unittest {
    // Test hex color parsing
    auto red = parseHexColor("#ff0000");
    assert(red.red > 0.99);
    assert(red.green < 0.01);
    assert(red.blue < 0.01);

    auto short3 = parseHexColor("#f00");
    assert(short3.red > 0.99);

    // Test hex color output
    RGBA rgba = new RGBA();
    rgba.red = 1.0;
    rgba.green = 0.5;
    rgba.blue = 0.0;
    auto hex = toHexColor(rgba);
    assert(hex == "#FF7F00" || hex == "#FF8000");  // Allow rounding

    // Test palette ID generation
    assert(generatePaletteId("Solarized Dark") == "solarized-dark");
    assert(generatePaletteId("Nord") == "nord");

    // Test palette parsing
    string testContent = `
[Palette]
Name=Test Palette

[Light]
Foreground=#000000
Background=#ffffff
Color0=#000000
Color1=#ff0000

[Dark]
Foreground=#ffffff
Background=#000000
Color0=#ffffff
Color1=#00ff00
`;
    auto palette = parsePaletteFile(testContent);
    assert(palette.name == "Test Palette");
    assert(palette.foreground[0].red < 0.01);  // Light fg is black
    assert(palette.foreground[1].red > 0.99);  // Dark fg is white

    // Test built-in palettes
    auto builtins = getBuiltinPalettes();
    assert(builtins.length >= 5);
    assert(builtins[0].name == "Tango");
    assert(builtins[0].isValid);

    // Test palette manager
    auto manager = new PaletteManager();
    assert(manager.palettes.length >= 5);
    assert(manager.current !is null);
    assert(manager.setCurrent("dracula"));
    assert(manager.current.name == "Dracula");
}
