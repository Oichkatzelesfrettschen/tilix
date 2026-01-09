/**
 * AT-SPI Type Definitions and Enumerations
 *
 * Core types used for accessibility via AT-SPI D-Bus interface.
 * Includes roles, states, event types, and coordinate systems.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.accessibility.atspi.types;

version (PURE_D_BACKEND):

/**
 * Accessibility role enumeration.
 * Describes the function/type of an accessible object.
 */
enum ATSPIRole : uint {
    Invalid = 0,
    Accelerator = 1,
    Alert = 2,
    AlertDialog = 3,
    Animation = 4,
    Application = 5,
    Arrow = 6,
    Calendar = 7,
    Canvas = 8,
    Caption = 9,
    CheckBox = 10,
    CheckMenuItem = 11,
    ColorChooser = 12,
    ColumnHeader = 13,
    ComboBox = 14,
    Comment = 15,
    DateEditor = 16,
    Dial = 17,
    Dialog = 18,
    DirectoryPane = 19,
    DrawingArea = 20,
    FileChooser = 21,
    Filler = 22,
    FontChooser = 23,
    Frame = 24,
    GlassPane = 25,
    HtmlContainer = 26,
    Icon = 27,
    Image = 28,
    InternalFrame = 29,
    Label = 30,
    LayeredPane = 31,
    List = 32,
    ListItem = 33,
    Menu = 34,
    MenuBar = 35,
    MenuItem = 36,
    OptionPane = 37,
    PageTab = 38,
    PageTabList = 39,
    Panel = 40,
    PasswordText = 41,
    PopupMenu = 42,
    ProgressBar = 43,
    PushButton = 44,
    RadioButton = 45,
    RadioMenuItem = 46,
    RootPane = 47,
    RowHeader = 48,
    Ruler = 49,
    ScrollBar = 50,
    ScrollPane = 51,
    Section = 52,
    Separator = 53,
    Slider = 54,
    SpinButton = 55,
    SplitPane = 56,
    StatusBar = 57,
    Table = 58,
    TableCell = 59,
    TableColumnHeader = 60,
    TableRowHeader = 61,
    TearoffMenuItem = 62,
    Terminal = 63,
    Text = 64,
    ToggleButton = 65,
    ToolBar = 66,
    ToolTip = 67,
    Tree = 68,
    TreeTable = 69,
    Unknown = 70,
    Viewport = 71,
    Window = 72,
    Header = 73,
    Footer = 74,
    Paragraph = 75,
    Autocomplete = 76,
    EditBar = 77,
    Embedded = 78,
    Entry = 79,
    Chart = 80,
    DocumentFrame = 81,
    Heading = 82,
    Page = 83,
    RedactedContent = 84,
    Landmark = 85,
}

/**
 * AT-SPI state enumeration.
 * Describes various states an accessible object can be in.
 */
enum ATSPIState : uint {
    Invalid = 0,
    Active = 1,
    Animated = 2,
    Armed = 3,
    Busy = 4,
    Checked = 5,
    Collapsed = 6,
    Defunct = 7,
    Editable = 8,
    Enabled = 9,
    Expandable = 10,
    Expanded = 11,
    Focusable = 12,
    Focused = 13,
    HasTooltip = 14,
    Horizontal = 15,
    Iconified = 16,
    Modal = 17,
    MultiLine = 18,
    Multiselectable = 19,
    Opaque = 20,
    Pressed = 21,
    Resizable = 22,
    Selectable = 23,
    Selected = 24,
    Sensitive = 25,
    Showing = 26,
    SingleLine = 27,
    Stale = 28,
    Transient = 29,
    Vertical = 30,
    Visible = 31,
    ManagesDescendants = 32,
    Indeterminate = 33,
    Required = 34,
    Truncated = 35,
    SupportsFill = 36,
    AlertNow = 37,
}

/**
 * AT-SPI text boundary type for text extraction.
 */
enum ATSPITextBoundary : uint {
    Char = 0,
    WordStart = 1,
    WordEnd = 2,
    SentenceStart = 3,
    SentenceEnd = 4,
    LineStart = 5,
    LineEnd = 6,
    ParagraphStart = 7,
    ParagraphEnd = 8,
}

/**
 * Coordinate type for GetExtents.
 */
enum ATSPICoordType : uint {
    ScreenRelative = 0,
    WindowRelative = 1,
    ParentRelative = 2,
}

/**
 * Rectangle structure for screen coordinates.
 */
struct ATSPIRect {
    int x;
    int y;
    int width;
    int height;
}

/**
 * State set represented as bit flags.
 */
struct ATSPIStateSet {
    ulong[2] states; // Bit set for up to 128 states

    void set(ATSPIState state) {
        uint stateNum = cast(uint)state;
        uint wordIndex = stateNum / 64;
        uint bitIndex = stateNum % 64;
        if (wordIndex < 2) {
            states[wordIndex] |= (1UL << bitIndex);
        }
    }

    void unset(ATSPIState state) {
        uint stateNum = cast(uint)state;
        uint wordIndex = stateNum / 64;
        uint bitIndex = stateNum % 64;
        if (wordIndex < 2) {
            states[wordIndex] &= ~(1UL << bitIndex);
        }
    }

    bool contains(ATSPIState state) const {
        uint stateNum = cast(uint)state;
        uint wordIndex = stateNum / 64;
        uint bitIndex = stateNum % 64;
        if (wordIndex < 2) {
            return (states[wordIndex] & (1UL << bitIndex)) != 0;
        }
        return false;
    }
}

/**
 * Event type enumeration.
 */
enum ATSPIEventType : uint {
    ObjectChanged = 0,
    ObjectChildrenChanged = 1,
    ObjectSelectionChanged = 2,
    ObjectVisibleDataChanged = 3,
    ObjectStateChanged = 4,
    TextCaretMoved = 5,
    TextChanged = 6,
    TextSelectionChanged = 7,
    WindowActivated = 8,
    WindowDeactivated = 9,
    WindowMinimized = 10,
    WindowMaximized = 11,
    WindowRestored = 12,
    WindowClosed = 13,
    FocusChanged = 14,
}

/**
 * Helper to create a state set with common terminal states.
 */
ATSPIStateSet terminalStateSet(bool focused, bool enabled) {
    ATSPIStateSet set;
    set.set(ATSPIState.Enabled);
    set.set(ATSPIState.Sensitive);
    set.set(ATSPIState.Showing);
    set.set(ATSPIState.Visible);
    set.set(ATSPIState.Focusable);
    if (focused) {
        set.set(ATSPIState.Focused);
    }
    return set;
}
