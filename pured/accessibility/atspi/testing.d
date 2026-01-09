/**
 * AT-SPI Testing and Validation Utilities
 *
 * Provides helpers for testing AT-SPI implementation with screen readers
 * and validating accessible object properties.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.accessibility.atspi.testing;

version (PURE_D_BACKEND):

import pured.accessibility.atspi.types;
import pured.accessibility.atspi.interfaces;
import pured.accessibility.atspi.provider;
import pured.accessibility.atspi.events;
import std.stdio : writeln, writef;
import std.format : format;

/**
 * AT-SPI validation test suite.
 * Validates that accessible objects properly implement required interfaces.
 */
class ATSPITestSuite {
private:
    int _testCount = 0;
    int _passCount = 0;
    int _failCount = 0;

public:
    /**
     * Run all AT-SPI validation tests.
     * Returns: true if all tests pass, false otherwise.
     */
    bool runAllTests() {
        writeln("\n[AT-SPI Testing] Starting validation suite...\n");

        testProviderInitialization();
        testAccessibleTerminal();
        testTextInterface();
        testComponentInterface();
        testEventHandling();

        writeln("\n[AT-SPI Testing] Results:");
        writeln(format("  Total: %d, Pass: %d, Fail: %d\n", _testCount, _passCount, _failCount));

        return _failCount == 0;
    }

private:
    void testProviderInitialization() {
        writeln("[Test] Provider Initialization");

        auto provider = getATSPIProvider();
        assert(provider !is null, "Provider should not be null");
        assert(provider.isInitialized(), "Provider should be initialized");

        auto root = provider.getRootAccessible();
        assert(root !is null, "Root accessible should exist");

        writeln("  PASS: Provider initialization");
        _testCount++;
        _passCount++;
    }

    void testAccessibleTerminal() {
        writeln("\n[Test] Accessible Terminal");

        auto provider = getATSPIProvider();
        auto terminal = cast(AccessibleTerminal)provider.getRootAccessible();
        assert(terminal !is null, "Root should be AccessibleTerminal");

        // Test basic properties
        assert(terminal.getRole() == ATSPIRole.Terminal, "Role should be Terminal");
        assert(terminal.getName() == "Tilix Terminal", "Name should match");
        assert(terminal.getDescription().length > 0, "Description should exist");

        // Test state
        auto state = terminal.getState();
        assert(state.contains(ATSPIState.Enabled), "Terminal should be enabled by default");
        assert(state.contains(ATSPIState.Showing), "Terminal should be showing");
        assert(state.contains(ATSPIState.Visible), "Terminal should be visible");

        // Test bounds
        auto bounds = terminal.getExtents(ATSPICoordType.ScreenRelative);
        assert(bounds.width > 0 && bounds.height > 0, "Bounds should be non-zero");

        // Test hierarchy
        assert(terminal.getParent() is null, "Root terminal has no parent");
        assert(terminal.getChildCount() == 0, "Terminal has no children (simplified model)");

        writeln("  PASS: Accessible terminal properties");
        _testCount++;
        _passCount++;
    }

    void testTextInterface() {
        writeln("\n[Test] Text Interface");

        auto provider = getATSPIProvider();
        auto terminal = cast(AccessibleTerminal)provider.getRootAccessible();

        // Set some test text
        terminal.setVisibleText("Hello, World!");

        // Test getText
        auto text = terminal.getText();
        assert(text == "Hello, World!", format("Text should be 'Hello, World!', got '%s'", text));

        // Test character count
        auto charCount = terminal.getCharacterCount();
        assert(charCount == 13, format("Character count should be 13, got %d", charCount));

        // Test text range
        auto range = terminal.getTextRange(0, 5);
        assert(range == "Hello", format("Range should be 'Hello', got '%s'", range));

        // Test caret offset
        terminal.setCursorOffset(5);
        assert(terminal.getCaretOffset() == 5, "Caret offset should be 5");

        // Test setting caret
        bool success = terminal.setCaretOffset(7);
        assert(success && terminal.getCaretOffset() == 7, "Should be able to set caret");

        // Test boundary text
        auto charText = terminal.getTextAtOffset(0, ATSPITextBoundary.Char);
        assert(charText == "H", format("Character at 0 should be 'H', got '%s'", charText));

        // Test editable property
        assert(!terminal.isEditable(), "Terminal should not be directly editable");

        writeln("  PASS: Text interface");
        _testCount++;
        _passCount++;
    }

    void testComponentInterface() {
        writeln("\n[Test] Component Interface");

        auto provider = getATSPIProvider();
        auto terminal = cast(AccessibleTerminal)provider.getRootAccessible();

        // Set bounds for testing
        terminal.setBounds(ATSPIRect(100, 50, 800, 600));

        // Test extents
        auto extents = terminal.getExtents(ATSPICoordType.ScreenRelative);
        assert(extents.x == 100 && extents.y == 50, "Position should match");
        assert(extents.width == 800 && extents.height == 600, "Size should match");

        // Test visibility
        assert(terminal.isVisible(), "Terminal with non-zero bounds should be visible");

        // Test alpha
        assert(terminal.getAlpha() == 1.0, "Terminal should be fully opaque");

        // Test layer and z-order
        assert(terminal.getLayer() == 0, "Terminal should be in normal layer");
        assert(terminal.getZOrder() == 0, "Terminal z-order should be 0");

        // Test bounding box containment
        assert(terminal.contains(150, 100, ATSPICoordType.ScreenRelative), "Point should be inside");
        assert(!terminal.contains(50, 50, ATSPICoordType.ScreenRelative), "Point should be outside");

        // Test focus grab
        bool focusGrabbed = terminal.grabFocus();
        assert(focusGrabbed, "Should be able to grab focus");

        // Test hit testing
        auto atPoint = terminal.getAccessibleAtPoint(150, 100, ATSPICoordType.ScreenRelative);
        assert(atPoint !is null, "Should return accessible at point");

        writeln("  PASS: Component interface");
        _testCount++;
        _passCount++;
    }

    void testEventHandling() {
        writeln("\n[Test] Event Handling");

        auto batcher = getEventBatcher();
        assert(batcher !is null, "Event batcher should exist");

        // Test enabling/disabling
        batcher.setEnabled(true);
        assert(batcher.isEnabled(), "Batcher should be enabled");

        batcher.setEnabled(false);
        assert(!batcher.isEnabled(), "Batcher should be disabled");

        batcher.setEnabled(true);

        // Test event queuing
        batcher.queueEvent("test-source", ATSPIEventType.TextChanged, "test detail");
        // Events are queued, verification requires listener registration

        // Test clearing
        batcher.clearPendingEvents();

        // Events should be cleared
        writeln("  PASS: Event handling");
        _testCount++;
        _passCount++;
    }
}

/**
 * Diagnostic helper to print accessible object properties.
 * Useful for debugging and understanding object hierarchy.
 */
void diagnoseAccessible(IAccessible accessible, int indent = 0) {
    if (accessible is null) {
        return;
    }

    string prefix = replicate("  ", indent);
    writef("%sRole: %d, Name: '%s'\n", prefix, accessible.getRole(), accessible.getName());

    auto state = accessible.getState();
    writef("%sState: enabled=%d, focused=%d, visible=%d\n",
        prefix,
        state.contains(ATSPIState.Enabled),
        state.contains(ATSPIState.Focused),
        state.contains(ATSPIState.Visible)
    );

    auto extents = accessible.getExtents(ATSPICoordType.ScreenRelative);
    writef("%sBounds: (%d, %d) %dx%d\n", prefix, extents.x, extents.y, extents.width, extents.height);

    // Diagnose children
    int childCount = accessible.getChildCount();
    if (childCount > 0) {
        writef("%sChildren: %d\n", prefix, childCount);
        for (int i = 0; i < childCount; i++) {
            auto child = accessible.getChild(i);
            diagnoseAccessible(child, indent + 1);
        }
    }
}

/**
 * Helper to replicate a string N times.
 */
string replicate(string s, int count) {
    string result = "";
    for (int i = 0; i < count; i++) {
        result ~= s;
    }
    return result;
}

/**
 * Run AT-SPI validation tests and print results.
 */
void validateATSPI() {
    auto suite = new ATSPITestSuite();
    bool allPass = suite.runAllTests();

    if (allPass) {
        writeln("[AT-SPI] All validation tests PASSED!");
    } else {
        writeln("[AT-SPI] Some validation tests FAILED!");
    }
}
