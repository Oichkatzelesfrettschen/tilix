/**
 * Triple Buffer
 *
 * Lock-free triple buffer for producer/consumer frame handoff.
 * Writer updates the back buffer and calls publish(); reader calls consume()
 * to swap in the newest frame when available.
 */
module pured.util.triplebuffer;

version (PURE_D_BACKEND):

import core.atomic;

struct TripleBuffer(T) {
private:
    T[3] _buffers;
    shared int _front;
    shared int _middle;
    shared int _back;
    shared bool _hasNew;

public:
    void reset() {
        atomicStore!(MemoryOrder.raw)(_front, 0);
        atomicStore!(MemoryOrder.raw)(_middle, 1);
        atomicStore!(MemoryOrder.raw)(_back, 2);
        atomicStore!(MemoryOrder.raw)(_hasNew, false);
    }

    @property ref T bufferAt(size_t index) return {
        assert(index < _buffers.length);
        return _buffers[index];
    }

    @property ref T writeBuffer() return {
        return _buffers[atomicLoad!(MemoryOrder.raw)(_back)];
    }

    void publish() {
        int back = atomicLoad!(MemoryOrder.raw)(_back);
        int middle = atomicLoad!(MemoryOrder.raw)(_middle);
        atomicStore!(MemoryOrder.raw)(_back, middle);
        atomicStore!(MemoryOrder.raw)(_middle, back);
        atomicStore!(MemoryOrder.rel)(_hasNew, true);
    }

    bool consume() {
        if (!atomicLoad!(MemoryOrder.acq)(_hasNew)) {
            return false;
        }
        int front = atomicLoad!(MemoryOrder.raw)(_front);
        int middle = atomicLoad!(MemoryOrder.raw)(_middle);
        atomicStore!(MemoryOrder.raw)(_front, middle);
        atomicStore!(MemoryOrder.raw)(_middle, front);
        atomicStore!(MemoryOrder.rel)(_hasNew, false);
        return true;
    }

    @property ref T readBuffer() return {
        return _buffers[atomicLoad!(MemoryOrder.acq)(_front)];
    }

    @property bool hasNewFrame() const return {
        return atomicLoad!(MemoryOrder.acq)(_hasNew);
    }
}
