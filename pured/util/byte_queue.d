/**
 * Byte queue for PTY parser handoff (thread-safe).
 */
module pured.util.byte_queue;

version (PURE_D_BACKEND):

import core.atomic : atomicLoad, atomicStore, MemoryOrder;
import core.sync.condition : Condition;
import core.sync.mutex : Mutex;

class ByteQueue {
private:
    Mutex _mutex;
    Condition _notEmpty;
    ubyte[][] _queue;
    shared bool _closed;

public:
    this() {
        _mutex = new Mutex();
        _notEmpty = new Condition(_mutex);
    }

    void push(const(ubyte)[] data) {
        if (data.length == 0) {
            return;
        }
        _mutex.lock();
        scope(exit) _mutex.unlock();

        if (atomicLoad!(MemoryOrder.raw)(_closed)) {
            return;
        }

        ubyte[] copy;
        copy.length = data.length;
        foreach (i; 0 .. data.length) {
            copy[i] = data[i];
        }

        _queue ~= copy;
        _notEmpty.notify();
    }

    bool pop(ref ubyte[] outData) {
        _mutex.lock();
        scope(exit) _mutex.unlock();

        while (_queue.length == 0 && !atomicLoad!(MemoryOrder.raw)(_closed)) {
            _notEmpty.wait();
        }

        if (_queue.length == 0) {
            outData.length = 0;
            return false;
        }

        outData = _queue[0];
        _queue = _queue[1 .. $];
        return true;
    }

    void close() {
        _mutex.lock();
        scope(exit) _mutex.unlock();
        atomicStore!(MemoryOrder.raw)(_closed, true);
        _notEmpty.notifyAll();
    }

    @property bool closed() const {
        return atomicLoad!(MemoryOrder.raw)(_closed);
    }
}
