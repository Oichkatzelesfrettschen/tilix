module pured.theme_importer;

version (PURE_D_BACKEND):

import pured.config : ThemeConfig;
import std.conv : to;
import std.file : exists, readText;
import std.ascii : isWhite;
import std.stdio : stderr;
import std.string : strip, toLower, lastIndexOf, startsWith, endsWith, indexOf, splitLines;

bool loadThemeFromFile(string path, string format, ref ThemeConfig outTheme) {
    if (!exists(path)) {
        stderr.writefln("Warning: Theme file not found: %s", path);
        return false;
    }
    auto data = readText(path);
    auto fmt = format.length == 0 ? detectFormat(path) : toLower(format);
    if (fmt == "xresources" || fmt == "xrdb") {
        return parseXresources(data, outTheme);
    }
    if (fmt == "alacritty") {
        return parseAlacritty(data, outTheme);
    }
    stderr.writefln("Warning: Unknown theme format '%s' for %s", fmt, path);
    return false;
}

private string detectFormat(string path) {
    auto lower = toLower(path);
    if (lower.endsWith(".xresources") || lower.endsWith(".xdefaults")) {
        return "xresources";
    }
    if (lower.endsWith(".yml") || lower.endsWith(".yaml")) {
        return "alacritty";
    }
    return "";
}
private string stripYamlComment(string line) {
    foreach (idx, ch; line) {
        if (ch == '#') {
            if (idx == 0 || line[idx - 1].isWhite) {
                return line[0 .. idx];
            }
        }
    }
    return line;
}

private bool parseHexColor(string value, out float[] rgba) {
    auto v = strip(value);
    if (v.length == 0) {
        return false;
    }
    if ((v[0] == '"' && v[$ - 1] == '"') || (v[0] == '\'' && v[$ - 1] == '\'')) {
        v = v[1 .. $ - 1];
    }
    if (v.startsWith("0x")) {
        v = v[2 .. $];
    }
    if (v.length > 0 && v[0] == '#') {
        v = v[1 .. $];
    }
    if (v.length != 6 && v.length != 8) {
        return false;
    }
    try {
        uint r = to!uint("0x" ~ v[0 .. 2]);
        uint g = to!uint("0x" ~ v[2 .. 4]);
        uint b = to!uint("0x" ~ v[4 .. 6]);
        uint a = v.length == 8 ? to!uint("0x" ~ v[6 .. 8]) : 0xFF;
        rgba = [r / 255.0f, g / 255.0f, b / 255.0f, a / 255.0f];
        return true;
    } catch (Exception) {
        return false;
    }
}

private void ensurePalette(ref ThemeConfig theme) {
    if (theme.palette.length < 16) {
        theme.palette.length = 16;
    }
}

private int colorIndexForName(string name, bool bright) {
    switch (name) {
        case "black": return bright ? 8 : 0;
        case "red": return bright ? 9 : 1;
        case "green": return bright ? 10 : 2;
        case "yellow": return bright ? 11 : 3;
        case "blue": return bright ? 12 : 4;
        case "magenta": return bright ? 13 : 5;
        case "cyan": return bright ? 14 : 6;
        case "white": return bright ? 15 : 7;
        default: return -1;
    }
}
private bool parseXresources(string data, ref ThemeConfig outTheme) {
    size_t hits = 0;
    foreach (line; splitLines(data)) {
        auto trimmed = strip(line);
        if (trimmed.length == 0) {
            continue;
        }
        if (trimmed[0] == '!' || trimmed[0] == '#') {
            continue;
        }
        auto sep = indexOf(trimmed, ":");
        if (sep < 0) {
            sep = indexOf(trimmed, "=");
        }
        if (sep < 0) {
            continue;
        }
        auto key = strip(trimmed[0 .. sep]);
        auto value = strip(trimmed[sep + 1 .. $]);
        auto keyLower = toLower(key);
        auto dot = lastIndexOf(keyLower, '.');
        auto star = lastIndexOf(keyLower, '*');
        auto cut = dot > star ? dot : star;
        if (cut >= 0 && cast(size_t)cut + 1 < keyLower.length) {
            keyLower = keyLower[cut + 1 .. $];
        }
        float[] rgba;
        if (!parseHexColor(value, rgba)) {
            continue;
        }
        if (keyLower == "foreground") {
            outTheme.foreground = rgba;
            hits++;
        } else if (keyLower == "background") {
            outTheme.background = rgba;
            hits++;
        } else if (startsWith(keyLower, "color")) {
            auto idxText = keyLower.length > 5 ? keyLower[5 .. $] : "";
            try {
                auto idx = to!int(idxText);
                if (idx >= 0 && idx < 16) {
                    ensurePalette(outTheme);
                    outTheme.palette[idx] = rgba;
                    hits++;
                }
            } catch (Exception) {
            }
        }
    }
    return hits > 0;
}
private int countLeadingSpaces(string line) {
    int count = 0;
    foreach (ch; line) {
        if (ch == ' ') {
            count++;
        } else if (ch == '\t') {
            count += 4;
        } else {
            break;
        }
    }
    return count;
}

private bool applyAlacrittyKey(string key, string value, ref ThemeConfig theme) {
    auto lower = toLower(key);
    float[] rgba;
    if (!parseHexColor(value, rgba)) {
        return false;
    }
    if (indexOf(lower, "primary.foreground") >= 0) {
        theme.foreground = rgba;
        return true;
    }
    if (indexOf(lower, "primary.background") >= 0) {
        theme.background = rgba;
        return true;
    }
    bool bright = indexOf(lower, "bright.") >= 0;
    bool normal = indexOf(lower, "normal.") >= 0;
    if (bright || normal) {
        auto lastDot = lastIndexOf(lower, '.');
        if (lastDot >= 0 && cast(size_t)lastDot + 1 < lower.length) {
            auto name = lower[lastDot + 1 .. $];
            auto idx = colorIndexForName(name, bright);
            if (idx >= 0) {
                ensurePalette(theme);
                theme.palette[idx] = rgba;
                return true;
            }
        }
    }
    return false;
}
private bool applyAlacrittySection(string section, string key, string value,
        ref ThemeConfig theme) {
    auto lowerKey = toLower(key);
    float[] rgba;
    if (!parseHexColor(value, rgba)) {
        return false;
    }
    if (section == "primary") {
        if (lowerKey == "foreground") {
            theme.foreground = rgba;
            return true;
        }
        if (lowerKey == "background") {
            theme.background = rgba;
            return true;
        }
    }
    if (section == "normal" || section == "bright") {
        auto idx = colorIndexForName(lowerKey, section == "bright");
        if (idx >= 0) {
            ensurePalette(theme);
            theme.palette[idx] = rgba;
            return true;
        }
    }
    return false;
}

private bool parseAlacritty(string data, ref ThemeConfig outTheme) {
    size_t hits = 0;
    string section;
    int sectionIndent = -1;
    foreach (rawLine; splitLines(data)) {
        auto cleaned = stripYamlComment(rawLine);
        auto line = strip(cleaned);
        if (line.length == 0) {
            continue;
        }
        int indent = countLeadingSpaces(rawLine);
        if (section.length > 0 && indent <= sectionIndent) {
            section = "";
            sectionIndent = -1;
        }
        auto eq = indexOf(line, "=");
        auto sep = indexOf(line, ":");
        if (eq >= 0 && (sep < 0 || eq < sep)) {
            auto key = strip(line[0 .. eq]);
            auto value = strip(line[eq + 1 .. $]);
            if (applyAlacrittyKey(key, value, outTheme)) {
                hits++;
            }
            continue;
        }
        if (sep < 0) {
            continue;
        }
        auto key = strip(line[0 .. sep]);
        auto value = strip(line[sep + 1 .. $]);
        if (value.length == 0) {
            auto lower = toLower(key);
            if (lower == "primary" || lower == "normal" || lower == "bright") {
                section = lower;
                sectionIndent = indent;
            }
            continue;
        }
        if (applyAlacrittySection(section, key, value, outTheme)) {
            hits++;
        }
    }
    return hits > 0;
}
