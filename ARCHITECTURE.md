# Tilix Architecture

This document provides a high-level overview of the Tilix architecture.

## Directory Structure

The main source code for Tilix is located in the `source` directory. This directory is further divided into the following subdirectories:

* **`app.d`**: This is the main entry point for the application. It is responsible for parsing command-line arguments, initializing the GTK+ application, and creating the main application window.

* **`gx`**: This directory contains the core logic for the Tilix application. It is further divided into the following subdirectories:
    * **`gtk`**: This directory contains GTK+-related utility functions and widgets.
    * **`i18n`**: This directory contains internationalization and localization files.
    * **`tilix`**: This directory contains the core Tilix application logic, including session management, terminal manipulation, and preferences.
    * **`util`**: This directory contains general utility functions.

* **`secret`**: This directory contains code for handling sensitive information, such as passwords.

* **`x11`**: This directory contains X11-specific code.

## Application Flow

The Tilix application starts in the `app.d` file. This file is responsible for the following:

1. **Parsing command-line arguments**: The `app.d` file parses the command-line arguments to determine the user's desired action.

2. **Initializing the GTK+ application**: The `app.d` file initializes the GTK+ application and creates the main application window.

3. **Creating the main application window**: The `app.d` file creates the main application window, which is an instance of the `Tilix.AppWindow` class.

The `Tilix.AppWindow` class is the main window for the Tilix application. It is responsible for the following:

* **Managing sessions**: The `Tilix.AppWindow` class manages the user's sessions, which are represented by the `Tilix.Session` class.

* **Handling user input**: The `Tilix.AppWindow` class handles user input, such as keyboard shortcuts and mouse clicks.

* **Drawing the user interface**: The `Tilix.AppWindow` class is responsible for drawing the user interface, which includes the terminal grid, the sidebar, and the header bar.
