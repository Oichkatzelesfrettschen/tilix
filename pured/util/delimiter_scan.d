/**
 * SIMD delimiter scan (SSE2 fallback).
 *
 * Finds the first occurrence of either delimiter in a byte slice.
 */
module pured.util.delimiter_scan;

version (PURE_D_BACKEND):

import core.bitop : bsf;

version (X86_64) {
    import inteli.emmintrin : __m128i, _mm_cmpeq_epi8, _mm_loadu_si128,
        _mm_movemask_epi8, _mm_or_si128, _mm_set1_epi8;
}
version (X86) {
    import inteli.emmintrin : __m128i, _mm_cmpeq_epi8, _mm_loadu_si128,
        _mm_movemask_epi8, _mm_or_si128, _mm_set1_epi8;
}

size_t findDelimiter(const(ubyte)[] data, ubyte delimA, ubyte delimB) nothrow @nogc {
    size_t len = data.length;
    if (len == 0) {
        return size_t.max;
    }

    version (X86_64) {
        enum block = 16;
        size_t i = 0;
        __m128i d1 = _mm_set1_epi8(cast(byte)delimA);
        __m128i d2 = _mm_set1_epi8(cast(byte)delimB);

        for (; i + block <= len; i += block) {
            __m128i chunk = _mm_loadu_si128(cast(const(__m128i)*)&data[i]);
            __m128i eq1 = _mm_cmpeq_epi8(chunk, d1);
            __m128i eq2 = _mm_cmpeq_epi8(chunk, d2);
            __m128i hits = _mm_or_si128(eq1, eq2);
            uint mask = cast(uint)_mm_movemask_epi8(hits);
            if (mask != 0) {
                return i + bsf(mask);
            }
        }

        for (; i < len; i++) {
            auto v = data[i];
            if (v == delimA || v == delimB) {
                return i;
            }
        }

        return size_t.max;
    } else version (X86) {
        enum block = 16;
        size_t i = 0;
        __m128i d1 = _mm_set1_epi8(cast(byte)delimA);
        __m128i d2 = _mm_set1_epi8(cast(byte)delimB);

        for (; i + block <= len; i += block) {
            __m128i chunk = _mm_loadu_si128(cast(const(__m128i)*)&data[i]);
            __m128i eq1 = _mm_cmpeq_epi8(chunk, d1);
            __m128i eq2 = _mm_cmpeq_epi8(chunk, d2);
            __m128i hits = _mm_or_si128(eq1, eq2);
            uint mask = cast(uint)_mm_movemask_epi8(hits);
            if (mask != 0) {
                return i + bsf(mask);
            }
        }

        for (; i < len; i++) {
            auto v = data[i];
            if (v == delimA || v == delimB) {
                return i;
            }
        }

        return size_t.max;
    } else {
        foreach (i, v; data) {
            if (v == delimA || v == delimB) {
                return i;
            }
        }
        return size_t.max;
    }
}
