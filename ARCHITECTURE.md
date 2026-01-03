# Tilix Architecture

This document provides a comprehensive architectural overview of Tilix, a tiling terminal emulator for Linux built with GTK+ 3 and the D programming language.

## Overview

Tilix is a feature-rich terminal emulator that allows users to organize multiple terminal sessions in a tiled layout. The application follows the Model-View-Controller (MVC) pattern and leverages the GTK+ 3 toolkit through the GtkD bindings for the D programming language.

### Key Technologies

- **Language**: D programming language
- **UI Framework**: GTK+ 3 (via GtkD bindings version 3.11.0)
- **Terminal Widget**: VTE (Virtual Terminal Emulator) widget
- **Build Systems**: Dub (D package manager) and Meson
- **Configuration**: GSettings/dconf for user preferences
- **Platform**: Linux with X11 support

## Directory Structure

The source code is organized in the `source` directory with the following structure:

### Top-Level Files

* **`app.d`**: Main entry point for the application. Initializes the GTK+ runtime, processes command-line arguments, and bootstraps the Tilix application class.

### Core Modules (`source/gx`)

The `gx` namespace contains the core application logic:

#### `gx/gtk/` - GTK+ Utilities
Platform-specific GTK+ utility functions and extensions:
- **`actions.d`**: Action management helpers
- **`cairo.d`**: Cairo graphics utilities
- **`clipboard.d`**: Clipboard operations
- **`color.d`**: Color manipulation utilities
- **`dialog.d`**: Dialog helpers
- **`resource.d`**: Resource management
- **`settings.d`**: GTK settings utilities
- **`threads.d`**: Thread management for GTK
- **`util.d`**: General GTK utilities
- **`vte.d`**: VTE widget extensions and utilities
- **`x11.d`**: X11-specific functionality

#### `gx/i18n/` - Internationalization
- **`l10n.d`**: Localization support for multi-language interface

#### `gx/tilix/` - Core Application Logic
The heart of the Tilix application:

**Main Application Components:**
- **`application.d`**: The `Tilix` class - GTK Application implementation, handles application lifecycle, menu management, and global actions
- **`appwindow.d`**: The `AppWindow` class - Main application window, manages sessions, sidebar, and window-level UI
- **`session.d`**: The `Session` class - Manages a group of tiled terminals, handles layout serialization/deserialization
- **`common.d`**: Shared interfaces and base classes
- **`constants.d`**: Application-wide constants
- **`cmdparams.d`**: Command-line parameter parsing
- **`preferences.d`**: User preferences management and ProfileManager
- **`colorschemes.d`**: Color scheme management
- **`encoding.d`**: Character encoding support
- **`sidebar.d`**: Sidebar UI for session navigation
- **`shortcuts.d`**: Keyboard shortcut definitions
- **`closedialog.d`**: Dialog for confirming window/terminal closure
- **`customtitle.d`**: Custom title functionality for terminals

**Bookmark Management (`gx/tilix/bookmark/`):**
- **`manager.d`**: Bookmark manager implementation
- **`bmeditor.d`**: Bookmark editor dialog
- **`bmchooser.d`**: Bookmark chooser widget
- **`bmtreeview.d`**: Tree view for bookmarks

**Preferences Editor (`gx/tilix/prefeditor/`):**
- **`prefdialog.d`**: Main preferences dialog
- **`profileeditor.d`**: Profile editor for terminal profiles
- **`bookmarkeditor.d`**: Bookmark preferences
- **`titleeditor.d`**: Title template editor
- **`advdialog.d`**: Advanced preferences dialog
- **`common.d`**: Shared preferences UI components

**Terminal Components (`gx/tilix/terminal/`):**
- **`terminal.d`**: The `Terminal` class - Main terminal widget wrapper around VTE
- **`exvte.d`**: Extended VTE functionality
- **`layout.d`**: Terminal layout management
- **`actions.d`**: Terminal-specific actions
- **`search.d`**: Search functionality within terminals
- **`regex.d`**: Regular expression support for terminal
- **`advpaste.d`**: Advanced paste dialog with safety warnings
- **`password.d`**: Password input handling
- **`monitor.d`**: Process monitoring within terminals
- **`activeprocess.d`**: Active process detection
- **`util.d`**: Terminal utilities

#### `gx/util/` - General Utilities
General-purpose utility functions used throughout the application.

### Platform-Specific Modules

* **`secret/` and `secretc/`**: Integration with libsecret for secure credential storage
* **`x11/`**: X11 window system integration for features like transparency and window positioning

## Application Flow

### Startup Sequence

1. **Application Bootstrap** (`app.d`):
   - Initialize D runtime and logging
   - Set up environment variables (PWD, XDG_CURRENT_DESKTOP)
   - Parse initial command-line arguments
   - Initialize GTK+ main loop via `gtk.Main`
   - Create the `Tilix` application singleton

2. **Application Initialization** (`application.d`):
   - Register the GApplication with D-Bus
   - Load application resources and CSS themes
   - Set up global actions (new session, quit, etc.)
   - Load user preferences from GSettings
   - Initialize bookmark manager
   - Handle command-line parameters for new windows/sessions

3. **Window Creation** (`appwindow.d`):
   - Create `AppWindow` instance (extends GTK ApplicationWindow)
   - Set up header bar and menu
   - Initialize sidebar for session navigation
   - Create initial session based on command-line arguments or defaults

4. **Session Creation** (`session.d`):
   - Create `Session` instance (uses GTK Stack widget)
   - Initialize terminal panes in the requested layout
   - Load or apply default profile settings
   - Set up event handlers for terminal state changes

5. **Terminal Creation** (`terminal/terminal.d`):
   - Create `Terminal` composite widget (extends GTK EventBox)
   - Embed VTE widget for actual terminal emulation
   - Add title bar, overlays, and notification support
   - Spawn shell process or execute command
   - Connect signal handlers for process events

### Core Architecture Components

#### The Tilix Application Class

The `Tilix` class extends GTK's `Application` and serves as the central coordinator:
- **Single Instance**: Uses D-Bus to enforce single-instance behavior
- **Session Management**: Manages multiple `AppWindow` instances
- **Global Actions**: Handles application-wide commands (new window, preferences, quit)
- **Resource Management**: Loads CSS themes, icons, and other resources
- **Command Handling**: Processes commands from command-line or D-Bus

#### The AppWindow Class

The `AppWindow` class represents a top-level application window:
- **Multi-Session Container**: Hosts multiple `Session` objects via tabs or sidebar
- **UI Shell**: Provides header bar, menus, and navigation controls
- **Window State**: Manages fullscreen, maximize, and quake mode
- **Drag-and-Drop**: Supports dragging terminals between windows
- **Notifications**: Handles desktop notifications for terminal events

#### The Session Class

The `Session` class represents a collection of tiled terminals:
- **Layout Management**: Implements recursive paned layout using GTK Paned widgets
- **Serialization**: Can save/load session layouts to/from JSON
- **Terminal Lifecycle**: Creates, destroys, and manages Terminal instances
- **Focus Management**: Tracks and manages terminal focus
- **Input Synchronization**: Can broadcast input to multiple terminals
- **State Tracking**: Monitors terminal states (maximized, titles, output)

#### The Terminal Class

The `Terminal` class is a composite widget wrapping the VTE terminal:
- **VTE Integration**: Embeds and manages the actual VTE terminal widget
- **Title Bar**: Optional title bar with terminal name and controls
- **Process Management**: Spawns shell/commands, monitors process state
- **Search**: Integrated search functionality
- **Custom Links**: Supports custom hyperlink detection
- **Badges**: Visual badges for terminal states
- **Triggers**: Can automatically switch profiles based on directory/hostname

### Data Flow

1. **User Input Flow**:
   ```
   Keyboard/Mouse → GTK Event → AppWindow → Session → Terminal → VTE → Shell
   ```

2. **Terminal Output Flow**:
   ```
   Shell → VTE → Terminal (triggers/badges) → Session (notifications) → AppWindow (UI updates)
   ```

3. **Configuration Flow**:
   ```
   GSettings (dconf) → Preferences → ProfileManager → Terminal (apply settings)
   ```

4. **Layout Persistence**:
   ```
   Session → JSON Serialization → Disk File
   Disk File → JSON Deserialization → Session → Terminal Creation
   ```

## Design Patterns

### Hierarchical Composition
The application uses a clear hierarchy:
```
Tilix (Application)
  └─ AppWindow (Window)
      └─ Session (Tab/Stack)
          └─ TerminalPaned (Layout)
              └─ Terminal (Widget)
                  └─ VTE (Native Terminal)
```

### Interface-Based Design
Key interfaces define contracts:
- **`IIdentifiable`**: Objects that have UUIDs (windows, sessions, terminals)
- **`ITerminal`**: Terminal interface for polymorphic terminal handling

### Signal-Based Communication
GTK signals and D delegates are used for event-driven communication:
- Terminals emit signals for state changes
- Sessions observe terminals and propagate events
- AppWindows react to session state changes

### Factory Pattern
Profiles and sessions use factory-like creation patterns for consistency.

## Configuration and State Management

### User Preferences
- **Storage**: GSettings/dconf database
- **Schema**: `com.gexperts.Tilix` namespace
- **Profiles**: Multiple terminal profiles with different settings
- **Persistence**: Automatic saving on changes

### Session State
- **Format**: JSON serialization
- **Location**: `~/.config/tilix/sessions/`
- **Contents**: Layout structure, terminal working directories, and commands

### Bookmarks
- **Storage**: JSON file in `~/.config/tilix/bookmarks.json`
- **Management**: Via bookmark manager with CRUD operations

## Extension Points

### Color Schemes
Custom color schemes can be added by creating JSON files in:
- System: `/usr/share/tilix/schemes/`
- User: `~/.config/tilix/schemes/`

### Keyboard Shortcuts
All shortcuts are configurable via GSettings and can be customized through the preferences dialog.

### Triggers and Badges
With patched VTE, terminals can:
- Automatically switch profiles based on directory or hostname
- Display custom badges based on terminal state

## Build System

### Dub (D Build Tool)
- **Configuration**: `dub.json`
- **Dependencies**: GtkD 3.11.0 (gtkd and vte packages)
- **Build Types**: release, debug, localize
- **Configurations**: default, trace, dynamic

### Meson
- **Configuration**: `meson.build`
- **Advantages**: Better integration with Linux distributions
- **Post-Install**: Schema compilation, icon cache update

## Internationalization

- **Framework**: GNU gettext via GtkD
- **Translation Platform**: Weblate
- **String Extraction**: `extract-strings.sh` script
- **PO Files**: Located in `po/` directory

## Performance Considerations

- **Terminal Efficiency**: VTE handles the heavy lifting of terminal emulation
- **Layout Updates**: GTK's native layout system manages complex tiling
- **Memory**: Each terminal runs a separate shell process
- **Responsiveness**: GTK main loop ensures UI responsiveness

## Security Considerations

- **Password Input**: Special handling via libsecret integration
- **Command Injection**: Proper escaping of shell commands
- **File Permissions**: Session and config files have user-only permissions
- **Process Isolation**: Each terminal runs in a separate process

## Future Architectural Considerations

See [TECHDEBT.md](TECHDEBT.md) and [ROADMAP.md](ROADMAP.md) for areas of potential architectural improvement and future development direction.
