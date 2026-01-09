/**
 * Wayland Data Device Bridge
 *
 * System clipboard support via wl_data_device protocol.
 * Provides copy/paste for the system clipboard (Ctrl+C/V).
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.platform.wayland.data_device.bridge;

version (PURE_D_BACKEND):

import core.stdc.errno : EAGAIN, EINTR, errno;
import core.sys.posix.poll : poll, pollfd, POLLIN;
import core.sys.posix.unistd : close, pipe, read, write;
import std.algorithm : min;
import std.array : appender;
import std.process : environment;
import std.string : fromStringz, toStringz;
import wayland.client.core;
import wayland.client.ifaces;
import wayland.client.opaque_types;
import wayland.client.protocol;
import wayland.client.util;

version (Dynamic) {
    import wayland.client.dy_loader : loadWaylandClient;
}

private struct OfferState {
    wl_data_offer* offer;
    string[] mimes;
}

/**
 * Wayland system clipboard bridge using wl_data_device.
 *
 * This provides access to the system clipboard (Ctrl+C/V),
 * as opposed to PRIMARY selection (middle-click paste).
 */
class WaylandDataDeviceBridge {
private:
    wl_display* _display;
    wl_registry* _registry;
    wl_seat* _seat;
    wl_pointer* _pointer;
    wl_keyboard* _keyboard;
    wl_data_device_manager* _manager;
    wl_data_device* _device;
    wl_data_source* _source;
    wl_data_offer* _currentOffer;
    OfferState[wl_data_offer*] _offers;
    string _ownedText;
    string _pendingText;
    bool _pendingSet;
    uint _lastSerial;
    bool _available;

public:
    this() {
        init();
    }

    ~this() {
        shutdown();
    }

    @property bool available() const {
        return _available;
    }

    void pump() {
        if (!_available || _display is null) {
            return;
        }
        wl_display_dispatch_pending(_display);
        wl_display_flush(_display);

        if (wl_display_prepare_read(_display) != 0) {
            if (errno == EAGAIN) {
                wl_display_dispatch_pending(_display);
            }
            return;
        }

        pollfd pfd;
        pfd.fd = wl_display_get_fd(_display);
        pfd.events = POLLIN;
        int ready = poll(&pfd, 1, 0);
        if (ready > 0 && (pfd.revents & POLLIN) != 0) {
            wl_display_read_events(_display);
            wl_display_dispatch_pending(_display);
        } else {
            wl_display_cancel_read(_display);
        }

        applyPendingSelection();
    }

    void setClipboard(string text) {
        if (!_available) {
            return;
        }
        _pendingText = text.idup;
        _pendingSet = true;
        applyPendingSelection();
    }

    string requestClipboard() {
        if (!_available || _currentOffer is null || _display is null) {
            return "";
        }
        auto state = _currentOffer in _offers;
        auto mime = chooseMime(state);
        if (mime.length == 0) {
            return "";
        }
        int[2] fds;
        if (pipe(fds) != 0) {
            return "";
        }
        wl_data_offer_receive(_currentOffer, mime.toStringz, fds[1]);
        close(fds[1]);
        wl_display_flush(_display);
        wl_display_roundtrip(_display);
        auto text = readAll(fds[0]);
        close(fds[0]);
        return text;
    }

private:
    void init() {
        auto displayName = environment.get("WAYLAND_DISPLAY", "");
        if (displayName.length == 0) {
            return;
        }
        version (Dynamic) {
            loadWaylandClient();
        }
        _display = wl_display_connect(null);
        if (_display is null) {
            return;
        }
        _registry = wl_display_get_registry(_display);
        if (_registry is null) {
            shutdown();
            return;
        }
        wl_registry_add_listener(_registry, &registryListener, cast(void*)this);
        wl_display_roundtrip(_display);
        if (_seat is null || _manager is null) {
            shutdown();
            return;
        }
        _device = wl_data_device_manager_get_data_device(_manager, _seat);
        if (_device is null) {
            shutdown();
            return;
        }
        wl_data_device_add_listener(_device, &deviceListener, cast(void*)this);
        wl_display_roundtrip(_display);
        _available = true;
    }

    void shutdown() {
        _available = false;
        clearSource();
        clearOffer(_currentOffer);
        _currentOffer = null;
        foreach (offer; _offers.keys) {
            clearOffer(cast(wl_data_offer*)offer);
        }
        _offers = null;
        if (_device !is null) {
            wl_data_device_destroy(_device);
            _device = null;
        }
        if (_manager !is null) {
            wl_data_device_manager_destroy(_manager);
            _manager = null;
        }
        if (_keyboard !is null) {
            wl_keyboard_destroy(_keyboard);
            _keyboard = null;
        }
        if (_pointer !is null) {
            wl_pointer_destroy(_pointer);
            _pointer = null;
        }
        if (_seat !is null) {
            wl_seat_destroy(_seat);
            _seat = null;
        }
        if (_registry !is null) {
            wl_registry_destroy(_registry);
            _registry = null;
        }
        if (_display !is null) {
            wl_display_disconnect(_display);
            _display = null;
        }
    }

    void applyPendingSelection() {
        if (!_pendingSet || _device is null || _manager is null || _lastSerial == 0) {
            return;
        }
        clearSource();
        _source = wl_data_device_manager_create_data_source(_manager);
        if (_source is null) {
            return;
        }
        wl_data_source_add_listener(_source, &sourceListener, cast(void*)this);
        wl_data_source_offer(_source, "text/plain;charset=utf-8".toStringz);
        wl_data_source_offer(_source, "text/plain".toStringz);
        wl_data_source_offer(_source, "UTF8_STRING".toStringz);
        wl_data_source_offer(_source, "TEXT".toStringz);
        wl_data_source_offer(_source, "STRING".toStringz);
        _ownedText = _pendingText;
        _pendingSet = false;
        wl_data_device_set_selection(_device, _source, _lastSerial);
        wl_display_flush(_display);
    }

    void clearSource() {
        if (_source !is null) {
            wl_data_source_destroy(_source);
            _source = null;
        }
    }

    void clearOffer(wl_data_offer* offer) {
        if (offer is null) {
            return;
        }
        if (offer in _offers) {
            _offers.remove(offer);
        }
        wl_data_offer_destroy(offer);
    }

    void updateSerial(uint serial) {
        _lastSerial = serial;
        applyPendingSelection();
    }

    void handleRegistryGlobal(wl_registry* registry, uint name, const(char)[] iface, uint ifaceVersion) {
        if (iface == "wl_seat" && _seat is null) {
            auto seatVersion = min(ifaceVersion, 5u);
            _seat = cast(wl_seat*)wl_registry_bind(registry, name, wl_seat_interface(), seatVersion);
            if (_seat !is null) {
                wl_seat_add_listener(_seat, &seatListener, cast(void*)this);
            }
            return;
        }
        if (iface == "wl_data_device_manager" && _manager is null) {
            auto managerVersion = min(ifaceVersion, 3u);
            _manager = cast(wl_data_device_manager*)wl_registry_bind(
                registry, name, wl_data_device_manager_interface(), managerVersion);
        }
    }

    void handleSeatCapabilities(uint capabilities) {
        if ((capabilities & WL_SEAT_CAPABILITY_POINTER) != 0) {
            if (_pointer is null) {
                _pointer = wl_seat_get_pointer(_seat);
                if (_pointer !is null) {
                    wl_pointer_add_listener(_pointer, &pointerListener, cast(void*)this);
                }
            }
        } else if (_pointer !is null) {
            wl_pointer_destroy(_pointer);
            _pointer = null;
        }

        if ((capabilities & WL_SEAT_CAPABILITY_KEYBOARD) != 0) {
            if (_keyboard is null) {
                _keyboard = wl_seat_get_keyboard(_seat);
                if (_keyboard !is null) {
                    wl_keyboard_add_listener(_keyboard, &keyboardListener, cast(void*)this);
                }
            }
        } else if (_keyboard !is null) {
            wl_keyboard_destroy(_keyboard);
            _keyboard = null;
        }
    }

    void handleDataOffer(wl_data_offer* offer) {
        if (offer is null) {
            return;
        }
        OfferState state;
        state.offer = offer;
        _offers[offer] = state;
        wl_data_offer_add_listener(offer, &offerListener, cast(void*)this);
    }

    void handleSelection(wl_data_offer* offer) {
        if (_currentOffer !is null && _currentOffer != offer) {
            clearOffer(_currentOffer);
        }
        _currentOffer = offer;
        if (offer is null) {
            return;
        }
        if (offer !in _offers) {
            OfferState state;
            state.offer = offer;
            _offers[offer] = state;
        }
    }

    void addOfferMime(wl_data_offer* offer, const(char)* mime) {
        if (offer is null || mime is null) {
            return;
        }
        auto state = offer in _offers;
        if (state is null) {
            OfferState newState;
            newState.offer = offer;
            _offers[offer] = newState;
            state = offer in _offers;
        }
        auto value = fromStringz(mime).idup;
        foreach (existing; state.mimes) {
            if (existing == value) {
                return;
            }
        }
        state.mimes ~= value;
    }

    void sendSourceText(int fd) {
        if (fd < 0) {
            return;
        }
        auto bytes = cast(const(ubyte)[])_ownedText;
        size_t offset = 0;
        while (offset < bytes.length) {
            auto written = write(fd, bytes.ptr + offset, bytes.length - offset);
            if (written < 0) {
                if (errno == EINTR) {
                    continue;
                }
                break;
            }
            offset += cast(size_t)written;
        }
        close(fd);
    }

    string readAll(int fd) {
        auto builder = appender!string();
        ubyte[4096] buffer;
        while (true) {
            auto count = read(fd, buffer.ptr, buffer.length);
            if (count < 0) {
                if (errno == EINTR) {
                    continue;
                }
                break;
            }
            if (count == 0) {
                break;
            }
            builder.put(cast(string)buffer[0 .. count]);
        }
        return builder.data.idup;
    }

    string chooseMime(OfferState* state) {
        if (state is null) {
            return "";
        }
        immutable string[] preferred = [
            "text/plain;charset=utf-8",
            "text/plain",
            "UTF8_STRING",
            "TEXT",
            "STRING"
        ];
        foreach (pref; preferred) {
            foreach (mime; state.mimes) {
                if (mime == pref) {
                    return mime;
                }
            }
        }
        return state.mimes.length > 0 ? state.mimes[0] : "";
    }

    // Registry listener callbacks
    extern (C) static void registryGlobal(void* data,
                                          wl_registry* registry,
                                          uint name,
                                          const(char)* ifaceName,
                                          uint ifaceVersion) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self is null) {
            return;
        }
        auto iface = ifaceName is null ? "" : fromStringz(ifaceName);
        self.handleRegistryGlobal(registry, name, iface, ifaceVersion);
    }

    extern (C) static void registryGlobalRemove(void* data, wl_registry*, uint) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self is null) {
            return;
        }
    }

    // Seat listener callbacks
    extern (C) static void seatCapabilities(void* data, wl_seat*, uint capabilities) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self is null) {
            return;
        }
        self.handleSeatCapabilities(capabilities);
    }

    extern (C) static void seatName(void*, wl_seat*, const(char)*) {
    }

    // Pointer listener callbacks
    extern (C) static void pointerEnter(void* data,
                                        wl_pointer*,
                                        uint serial,
                                        wl_surface*,
                                        wl_fixed_t,
                                        wl_fixed_t) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self !is null) {
            self.updateSerial(serial);
        }
    }

    extern (C) static void pointerLeave(void* data,
                                        wl_pointer*,
                                        uint serial,
                                        wl_surface*) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self !is null) {
            self.updateSerial(serial);
        }
    }

    extern (C) static void pointerMotion(void*, wl_pointer*, uint, wl_fixed_t, wl_fixed_t) {
    }

    extern (C) static void pointerButton(void* data,
                                         wl_pointer*,
                                         uint serial,
                                         uint,
                                         uint,
                                         uint) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self !is null) {
            self.updateSerial(serial);
        }
    }

    extern (C) static void pointerAxis(void*, wl_pointer*, uint, uint, wl_fixed_t) {
    }

    // Keyboard listener callbacks
    extern (C) static void keyboardKeymap(void*, wl_keyboard*, uint, int fd, uint) {
        if (fd >= 0) {
            close(fd);
        }
    }

    extern (C) static void keyboardEnter(void* data,
                                         wl_keyboard*,
                                         uint serial,
                                         wl_surface*,
                                         wl_array*) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self !is null) {
            self.updateSerial(serial);
        }
    }

    extern (C) static void keyboardLeave(void* data, wl_keyboard*, uint serial, wl_surface*) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self !is null) {
            self.updateSerial(serial);
        }
    }

    extern (C) static void keyboardKey(void* data,
                                       wl_keyboard*,
                                       uint serial,
                                       uint,
                                       uint,
                                       uint) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self !is null) {
            self.updateSerial(serial);
        }
    }

    extern (C) static void keyboardModifiers(void* data,
                                             wl_keyboard*,
                                             uint serial,
                                             uint,
                                             uint,
                                             uint,
                                             uint) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self !is null) {
            self.updateSerial(serial);
        }
    }

    extern (C) static void keyboardRepeatInfo(void*, wl_keyboard*, int, int) {
    }

    // Data device listener callbacks
    extern (C) static void deviceDataOffer(void* data,
                                           wl_data_device*,
                                           wl_data_offer* offer) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self !is null) {
            self.handleDataOffer(offer);
        }
    }

    extern (C) static void deviceEnter(void* data,
                                       wl_data_device*,
                                       uint serial,
                                       wl_surface*,
                                       wl_fixed_t,
                                       wl_fixed_t,
                                       wl_data_offer*) {
        // Drag-and-drop enter - not needed for clipboard
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self !is null) {
            self.updateSerial(serial);
        }
    }

    extern (C) static void deviceLeave(void* data, wl_data_device*) {
        // Drag-and-drop leave - not needed for clipboard
    }

    extern (C) static void deviceMotion(void* data,
                                        wl_data_device*,
                                        uint,
                                        wl_fixed_t,
                                        wl_fixed_t) {
        // Drag-and-drop motion - not needed for clipboard
    }

    extern (C) static void deviceDrop(void* data, wl_data_device*) {
        // Drag-and-drop drop - not needed for clipboard
    }

    extern (C) static void deviceSelection(void* data,
                                           wl_data_device*,
                                           wl_data_offer* offer) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self !is null) {
            self.handleSelection(offer);
        }
    }

    // Data offer listener callbacks
    extern (C) static void offerOffer(void* data,
                                      wl_data_offer* offer,
                                      const(char)* mime) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self !is null) {
            self.addOfferMime(offer, mime);
        }
    }

    // Data source listener callbacks
    extern (C) static void sourceTarget(void* data,
                                        wl_data_source*,
                                        const(char)*) {
        // Target accepted a mime type - informational
    }

    extern (C) static void sourceSend(void* data,
                                      wl_data_source*,
                                      const(char)*,
                                      int fd) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self !is null) {
            self.sendSourceText(fd);
        } else if (fd >= 0) {
            close(fd);
        }
    }

    extern (C) static void sourceCancelled(void* data,
                                           wl_data_source*) {
        auto self = cast(WaylandDataDeviceBridge*)data;
        if (self !is null) {
            self.clearSource();
            self._ownedText = "";
        }
    }

    // Listener structs
    private static __gshared wl_registry_listener registryListener = {
        &registryGlobal,
        &registryGlobalRemove
    };

    private static __gshared wl_seat_listener seatListener = {
        &seatCapabilities,
        &seatName
    };

    private static __gshared wl_pointer_listener pointerListener = {
        &pointerEnter,
        &pointerLeave,
        &pointerMotion,
        &pointerButton,
        &pointerAxis
    };

    private static __gshared wl_keyboard_listener keyboardListener = {
        &keyboardKeymap,
        &keyboardEnter,
        &keyboardLeave,
        &keyboardKey,
        &keyboardModifiers,
        &keyboardRepeatInfo
    };

    private static __gshared wl_data_device_listener deviceListener = {
        &deviceDataOffer,
        &deviceEnter,
        &deviceLeave,
        &deviceMotion,
        &deviceDrop,
        &deviceSelection
    };

    private static __gshared wl_data_offer_listener offerListener = {
        &offerOffer
    };

    private static __gshared wl_data_source_listener sourceListener = {
        &sourceTarget,
        &sourceSend,
        &sourceCancelled
    };
}
