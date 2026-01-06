module pured.text.shaper;

version (PURE_D_BACKEND):

import bindbc.hb;
import bindbc.hb.bind.ft;
import bindbc.hb.config : HBSupport;
import bindbc.hb.dynload : loadHarfBuzz;
import bindbc.freetype;
import std.stdio : stderr, writefln;

struct ShapedGlyph {
    uint glyphIndex;
    uint cluster;
    int xAdvance;
    int yAdvance;
    int xOffset;
    int yOffset;
}

class TextShaper {
private:
    hb_font_t* _font;
    hb_buffer_t* _buffer;
    bool _available;

public:
    bool initialize(FT_Face face, int fontSize) {
        auto hbRet = loadHarfBuzz();
        if (hbRet == HBSupport.noLibrary) {
            stderr.writefln("Warning: HarfBuzz library not found");
            _available = false;
            return true;
        }
        if (hbRet == HBSupport.badLibrary) {
            stderr.writefln("Warning: HarfBuzz library has missing symbols");
        }

        if (face is null) {
            stderr.writefln("Warning: HarfBuzz not initialized (no FreeType face)");
            _available = false;
            return true;
        }

        _font = hb_ft_font_create_referenced(face);
        if (_font is null) {
            stderr.writefln("Warning: HarfBuzz failed to create font");
            _available = false;
            return true;
        }

        hb_ft_font_set_load_flags(_font, FT_LOAD_DEFAULT);
        hb_font_set_scale(_font, fontSize * 64, fontSize * 64);
        hb_font_set_ppem(_font, cast(uint)fontSize, cast(uint)fontSize);

        _buffer = hb_buffer_create();
        if (_buffer is null) {
            stderr.writefln("Warning: HarfBuzz failed to create buffer");
            hb_font_destroy(_font);
            _font = null;
            _available = false;
            return true;
        }

        _available = true;
        return true;
    }

    void terminate() {
        if (_buffer !is null) {
            hb_buffer_destroy(_buffer);
            _buffer = null;
        }
        if (_font !is null) {
            hb_font_destroy(_font);
            _font = null;
        }
        _available = false;
    }

    @property bool available() const { return _available; }

    bool shapeLine(const(dchar)[] text, ref ShapedGlyph[] outGlyphs, out uint outLength) @nogc {
        outLength = 0;
        if (!_available || _buffer is null || _font is null || text.length == 0) {
            return false;
        }

        hb_buffer_clear_contents(_buffer);
        hb_buffer_add_utf32(_buffer, cast(const(uint)*)text.ptr,
                            cast(int)text.length, 0, cast(int)text.length);
        hb_buffer_guess_segment_properties(_buffer);

        hb_shape(_font, _buffer, null, 0);

        uint length = hb_buffer_get_length(_buffer);
        if (length == 0) {
            return true;
        }
        if (length > outGlyphs.length) {
            return false;
        }

        auto infos = hb_buffer_get_glyph_infos(_buffer, &length);
        auto positions = hb_buffer_get_glyph_positions(_buffer, &length);

        foreach (i; 0 .. length) {
            outGlyphs[i] = ShapedGlyph(
                infos[i].codepoint,
                infos[i].cluster,
                positions[i].x_advance,
                positions[i].y_advance,
                positions[i].x_offset,
                positions[i].y_offset
            );
        }
        outLength = length;
        return true;
    }
}
