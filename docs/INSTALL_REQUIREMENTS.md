# Tilix Build and Runtime Requirements (CachyOS/Arch)

This document lists the packages required to build and run Tilix, plus
optional stacks for GTK4, Qt, and framebuffer/KMS/DRM exploration.

## 1. Core D toolchain (required)
- dmd (reference compiler, includes Phobos)
- dmd-docs (optional)
- dtools (dfmt, dscanner, rdmd, etc.)
- dub
- ldc (optional but recommended for optimized builds)
- gcc-d (optional, GCC frontend)

Tested toolchain baseline:
- DMD 2.111.0
- LDC 1.41.0 (based on DMD 2.111.0)
- DUB 1.40.0

```sh
sudo pacman -S --needed dmd dtools dub ldc gcc-d
```

## 2. Build systems and tooling (required)
- git
- meson
- ninja
- pkgconf
- python

```sh
sudo pacman -S --needed git meson ninja pkgconf python
```

## 3. GTK3 + VTE3 (current default runtime)
- gtk3
- vte3
- vte-common
- gsettings-desktop-schemas
- libsecret (optional; enables keyring integration)
- xorg-x11 and common desktop libs are pulled in by GTK3/VTE

```sh
sudo pacman -S --needed gtk3 vte3 vte-common gsettings-desktop-schemas libsecret
```

## 4. GTK4 + VTE4 (optional future backend)
- gtk4
- vte4
- vte4-utils (optional; debugging tools)

```sh
sudo pacman -S --needed gtk4 vte4 vte4-utils
```

## 5. Qt backend (optional)
Tilix does not ship a Qt backend yet, but a future port can target QTermWidget.

- qt6-base
- qtermwidget
- cmake (if building qtermwidget from source)

```sh
sudo pacman -S --needed qt6-base qtermwidget cmake
```

## 6. Framebuffer / KMS / DRM (optional)
For direct rendering without GTK/Qt:
- libdrm
- mesa (GBM/EGL)
- libxkbcommon (keyboard mapping)
- libinput (input devices)
- seatd (logind alternative on non-systemd setups)

```sh
sudo pacman -S --needed libdrm mesa libxkbcommon libinput seatd
```

## 7. OpenGL/EGL (optional)
- mesa
- libglvnd
- libepoxy (OpenGL loader)

```sh
sudo pacman -S --needed mesa libglvnd libepoxy
```

## 8. Vulkan (optional)
- vulkan-icd-loader
- vulkan-headers
- shaderc
- glslang

```sh
sudo pacman -S --needed vulkan-icd-loader vulkan-headers shaderc glslang
```

## 9. Formal verification toolchain (optional)
Used for `verification/` specs and extraction workflows.

- coq
- ocaml
- z3
- python
- tla-toolbox (GUI) or tlaplus (CLI)

```sh
sudo pacman -S --needed coq ocaml z3 python tlaplus tla-toolbox
```

## 10. Install-time utilities (required for install.sh)
The install script uses these commands directly:
- glib-compile-schemas (glib2)
- glib-compile-resources (glib2)
- msgfmt (gettext)
- desktop-file-validate (desktop-file-utils)
- update-desktop-database (desktop-file-utils)
- gtk-update-icon-cache (gtk3)
- xdg-desktop-menu (xdg-utils)
- python (used by scripts/dub/prepare-resources.sh)

```sh
sudo pacman -S --needed glib2 gettext desktop-file-utils gtk3 xdg-utils python
```

## 11. Metadata + manpage tooling (optional but recommended)
- appstreamcli (appstream) for AppStream metadata validation
- po4a-translate (po4a) for localized man pages

```sh
sudo pacman -S --needed appstream po4a
```

## Notes
- For non-Arch distributions, map the packages above to your distro
  equivalents (Fedora, Debian/Ubuntu, etc.).
- The GTK3/VTE3 stack is required for the current Tilix codebase.
