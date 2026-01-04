import std.stdio;
import std.range;
import std.algorithm;

void main() {
    // Output 5 million lines of colored text to ensure sustained load
    foreach (i; 0 .. 5_000_000) {
        // Simple ANSI color cycling
        int color = 31 + (i % 7);
        writefln("\033[%dmLine %d: The quick brown fox jumps over the lazy dog\033[0m", color, i);
    }
}