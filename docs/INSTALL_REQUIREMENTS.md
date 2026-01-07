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

Optional config validation:
- python-jsonschema (for `scripts/pure-d/validate_config.sh`)

```sh
sudo pacman -S --needed python-jsonschema
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

## 4. Pure D backend (GLFW/OpenGL)
Pure D uses `dub --config=pure-d` and bypasses GTK/VTE.

System packages (X11-focused; GLFW may also be built with Wayland):
- glfw (window/input)
- freetype2 (glyph rasterization)
- mesa or libglvnd (libGL)
- libx11 libxrandr libxinerama libxcursor libxi (GLFW X11 deps)

```sh
sudo pacman -S --needed glfw freetype2 mesa libx11 libxrandr libxinerama libxcursor libxi
```

DUB/OS additions for advanced features (optional):
- harfbuzz (text shaping; required for ligatures/combining marks)
- fontconfig (fallback font discovery)
- libxkbcommon (keymap handling)
- libxcb + xcb-util-wm (required for X11 PRIMARY selection; also used for X11 window hints/Quake mode)
- xdg-utils (hyperlink activation via xdg-open)

```sh
sudo pacman -S --needed harfbuzz fontconfig libxkbcommon libxcb xcb-util-wm
```

Wayland (optional; PRIMARY selection via primary-selection-unstable-v1):
- wayland (ships wayland-scanner for regenerating protocol bindings)
- wayland-protocols (primary-selection XML)

```sh
sudo pacman -S --needed wayland wayland-protocols
```

DUB dependencies (pulled automatically; versions from code.dlang.org /latest):
- bindbc-glfw 1.1.2 (configured static in dub.json; ensure libglfw3.a exists)
- bindbc-opengl 1.1.1
- bindbc-loader 1.1.5
- bindbc-freetype 1.3.3
- arsd-official:terminalemulator 12.1.0
- mir-algorithm 3.22.4
- mir-ion 2.3.5 (JSON config)
- intel-intrinsics 1.13.0
- capnproto-dlang 0.1.2 (IPC schema + client)
- bindbc-harfbuzz 0.2.1 (shaping)
- bindbc-fontconfig 1.0.0 (fallback discovery)
- xkbcommon-d 0.5.1 (optional)
- xcb-d 2.1.1+1.11.1 (optional)
- xcb-util-wm-d 0.5.0+0.4.1 (optional)
- wayland-client-d 1.8.90 (optional)
- wayland-scanner-d 1.0.0 (optional; protocol generation)
- fswatch 0.6.1 or dinotify 0.5.0 (optional; config file watching)

Pure D module notes:
- Input/keybinding fallback: libxkbcommon (xkbcommon-d) for GLFW_KEY_UNKNOWN lookup.
- PRIMARY selection: libxcb + xcb-util-wm on X11; wayland + wayland-protocols on Wayland.
- Renderer/shaping: freetype2 + harfbuzz + fontconfig for glyphs and fallback.
- Hyperlink activation: xdg-utils for xdg-open.

## 5. GTK4 + VTE4 (optional future backend)
- gtk4
- vte4
- vte4-utils (optional; debugging tools)

```sh
sudo pacman -S --needed gtk4 vte4 vte4-utils
```

## 6. Qt backend (optional)
Tilix does not ship a Qt backend yet, but a future port can target QTermWidget.

- qt6-base
- qtermwidget
- cmake (if building qtermwidget from source)

```sh
sudo pacman -S --needed qt6-base qtermwidget cmake
```

## 7. Framebuffer / KMS / DRM (optional)
For direct rendering without GTK/Qt:
- libdrm
- mesa (GBM/EGL)
- libxkbcommon (keyboard mapping)
- libinput (input devices)
- seatd (logind alternative on non-systemd setups)

```sh
sudo pacman -S --needed libdrm mesa libxkbcommon libinput seatd
```

## 8. OpenGL/EGL and X11 (required for high-refresh rendering)
For the OpenGL render backend (bypasses VTE3's 40 FPS cap):
- mesa
- libglvnd
- libepoxy (OpenGL loader)
- freetype2 (font rasterization)
- fontconfig (font discovery)
- libxrandr (X11 refresh rate detection)
- libxpresent (X11 VSync support, future)

```sh
sudo pacman -S --needed mesa libglvnd libepoxy freetype2 fontconfig libxrandr libxpresent
```

D bindings (automatically fetched by DUB):
- bindbc-opengl 1.1.1
- bindbc-loader 1.1.5
- bindbc-freetype 1.3.3

## 9. Vulkan (optional)
- vulkan-icd-loader
- vulkan-headers
- shaderc
- glslang

```sh
sudo pacman -S --needed vulkan-icd-loader vulkan-headers shaderc glslang
```

## 10. Formal verification toolchain (optional)
Used for `verification/` specs and extraction workflows.

- coq
- ocaml
- z3
- python
- tla-toolbox (GUI) or tlaplus (CLI)

```sh
sudo pacman -S --needed coq ocaml z3 python tlaplus tla-toolbox
```

## 11. Install-time utilities (required for install.sh)
The install script uses these commands directly:
- glib-compile-schemas (glib2)
- glib-compile-resources (glib2)
- msgfmt (gettext)
- desktop-file-validate (desktop-file-utils)
- update-desktop-database (desktop-file-utils)
- gtk-update-icon-cache (gtk3)
- xdg-desktop-menu (xdg-utils)
- python (used by scripts/dub/prepare-resources.sh)
- gdk-pixbuf-pixdata (gdk-pixbuf2; used by resource compilation)
- realpath, install, find, sed, gzip (coreutils, findutils, sed, gzip)

```sh
sudo pacman -S --needed glib2 gettext desktop-file-utils gtk3 xdg-utils python gdk-pixbuf2 coreutils findutils sed gzip
```

## 12. Metadata + manpage tooling (optional but recommended)
- appstreamcli (appstream) for AppStream metadata validation
- po4a-translate (po4a) for localized man pages

```sh
sudo pacman -S --needed appstream po4a
```

## 13. IPC + automation (optional)
For IPC control plane and schema-driven commands:
- capnproto (capnp compiler for schema generation; used with capnproto-dlang)
- capnpc-dlang (Cap'n Proto D plugin; AUR on Arch)
- socat (useful for PTY/IPC testing)

```sh
sudo pacman -S --needed capnproto socat
yay -S --needed capnpc-dlang
```

Note: the DUB library `capnproto-dlang` is pulled automatically; only the
`capnpc-dlang` plugin is needed for schema generation.

## 14. Testing + benchmarking (optional)
- vttest (terminal correctness suite)
- hyperfine (benchmark runner)
- perf (linux-tools; profiling)

```sh
sudo pacman -S --needed vttest hyperfine perf
```

## 15. IME/input method stacks (optional)
If IME support is needed for non-Latin input:
- ibus, ibus-gtk
- fcitx5, fcitx5-gtk

```sh
sudo pacman -S --needed ibus ibus-gtk fcitx5 fcitx5-gtk
```

## Notes
- For non-Arch distributions, map the packages above to your distro
  equivalents (Fedora, Debian/Ubuntu, etc.).
- The GTK3/VTE3 stack is required for the current Tilix codebase.
- `dub-asan.json` ASAN builds require LDC and a compiler-rt/libasan package.
- `bindbc-glfw` is set to static in `dub.json`; ensure libglfw3.a exists or switch to dynamic.
- `scripts/dub/prepare-resources.sh` runs `appstreamcli validate` when present and treats warnings as errors.
