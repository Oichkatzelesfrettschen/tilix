/**
 * Byte ring buffer (SPSC).
 */
module pured.util.byte_ring;

version (PURE_D_BACKEND):

import std.algorithm : min, max;

struct ByteRing {
private:
    ubyte[] _buffer;
    size_t _mask;
    size_t _head;
    size_t _tail;

public:
    this(size_t capacity) {
        setCapacity(capacity);
    }

    void setCapacity(size_t capacity) {
        size_t cap = nextPow2(max(cast(size_t)2, capacity));
        _buffer.length = cap;
        _mask = cap - 1;
        _head = 0;
        _tail = 0;
    }

    @property size_t capacity() const @nogc nothrow {
        return _buffer.length;
    }

    @property size_t size() const @nogc nothrow {
        return _head - _tail;
    }

    @property size_t available() const @nogc nothrow {
        return _buffer.length - size;
    }

    @property bool isEmpty() const @nogc nothrow {
        return _head == _tail;
    }

    @property bool isFull() const @nogc nothrow {
        return size == _buffer.length;
    }

    size_t write(const(ubyte)[] data) @nogc nothrow {
        size_t toWrite = min(data.length, available);
        if (toWrite == 0) {
            return 0;
        }

        size_t head = _head;
        size_t headIndex = head & _mask;
        size_t first = min(toWrite, _buffer.length - headIndex);
        _buffer[headIndex .. headIndex + first] = data[0 .. first];

        size_t second = toWrite - first;
        if (second > 0) {
            _buffer[0 .. second] = data[first .. first + second];
        }

        _head += toWrite;
        return toWrite;
    }

    size_t read(ubyte[] outData) @nogc nothrow {
        size_t toRead = min(outData.length, size);
        if (toRead == 0) {
            return 0;
        }

        size_t tail = _tail;
        size_t tailIndex = tail & _mask;
        size_t first = min(toRead, _buffer.length - tailIndex);
        outData[0 .. first] = _buffer[tailIndex .. tailIndex + first];

        size_t second = toRead - first;
        if (second > 0) {
            outData[first .. first + second] = _buffer[0 .. second];
        }

        _tail += toRead;
        return toRead;
    }

private:
    static size_t nextPow2(size_t value) @nogc nothrow {
        size_t v = 1;
        while (v < value) {
            v <<= 1;
        }
        return v;
    }
}
