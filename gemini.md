# Gemini Audit and Roadmap

## Decision
DUB is the primary build system. Meson remains as a packaging fallback for distro
integration until DUB reaches feature parity across resources, i18n, schemas,
metadata, and install steps.

## Repository Walkthrough (Audit)
- source/: D modules for GTK wrappers, Tilix app core, X11 and secret storage.
- data/: icons, resources, UI files, schemas, desktop/appdata templates, scripts.
- po/: translation sources and manpage localization inputs.
- scripts/: install/uninstall helpers and benchmark tooling.
- docs/: requirements, audits, and research notes.
- verification/: formal methods specs and proof artifacts.
- experimental/: optional packaging and backend experiments.

## Ultra-detailed Re-audit (Interconnections)
- Entry: source/app.d -> gx.tilix.application -> gx.tilix.appwindow ->
  gx.tilix.session -> gx.tilix.terminal.* (layout, VTE, actions, search).
- GTK/VTE glue lives in source/gx/gtk/* and is used by terminal modules.
- Preferences and profiles flow through gx.tilix.prefeditor.* and
  gx.tilix.preferences -> gx.tilix.session.
- Resource pipeline: data/resources (gresource) + data/gsettings +
  data/pkg/desktop + data/metainfo + data/dbus + icons.
- i18n pipeline: po/*.po + data/man/po + msgfmt + po4a-translate.
- Security integration: source/secret/* and source/secretc/* for libsecret.
- X11 integration: source/x11/* for windowing/X11 features.
- Formal verification is isolated in verification/ with Coq, TLA+, and OCaml.

## Deficiencies and Risks (Current)
- Resource pipeline was split between Meson and install.sh; DUB lacked hooks.
- D-Bus service file was hardcoded to /usr/bin; prefix variance was not handled.
- Optional tooling (appstreamcli, po4a) was not documented alongside install.
- Warnings/deprecations were not enforced; now treated as errors via DUB.
- Strict builds require `DFLAGS=-w` enforced by `scripts/dub/strict-check.sh`.
- .claude directory permissions cause noisy git status warnings.
- OpenGLContainer remains a stub (metrics, selection, snapshot, encoding).
- Backend abstraction is still not wired through Terminal (per architectural audit).
- Pure D backend still missing: richer search UI, IPC command coverage beyond spawn-new-process placeholder, IME implementation, tab/split UI, perf handoff (triple buffer/PBO).
- Pure D theme import is best-effort parsing (no full YAML/Xresources grammar coverage).
- Wayland/XCB bindings are documented but not yet integrated into the runtime.

## Sanity Check
- DUB build succeeds with `DFLAGS=-w` after vendoring arsd-official and patching warnings.
- DUB runs resource preparation before builds via `scripts/dub/prepare-resources.sh`.
- Install uses staged artifacts to avoid polluting the source tree.
- Pure D backend now includes: clipboard/PRIMARY, true color, bell flash, cursor styles (incl. outline), selection + search highlights (configurable), hyperlink detection + Ctrl+click, HarfBuzz shaping + fallback, selection-driven search, hot-reloadable config, accessibility presets, IPC schema + local UNIX socket listener + DUB IPC client, strict `pure-d-nogc` build profile, SIMD delimiter/search unit tests, a headless test harness, and Quake/dropdown mode support.

## XPRA Crash Findings
- xpra server aborts with a pygobject assertion in pygi-invoke.c during
  gstreamer encoder selftest initialization.
- Running xpra with `--gstreamer=no` avoids the crash and keeps the session up.
- Debug logs include environment variables; treat them as sensitive artifacts.

## Feature Harvest Status
- Initial inventory captured in docs/research/feature-harvest.md.
- Backend interface draft captured in docs/architecture/backend-interface-map.md.
- Alacritty and kitty sources were pulled from upstream docs (no local repos).

## Testable Hypotheses and Validation Notes
- Tilix is GTK3 + VTE3 based: verified via dub.json dependencies.
- DUB supports preBuildCommands/postBuildCommands/buildRequirements/targetType=none: verify via DUB build settings reference: https://dub.pm/dub-reference/build_settings/
- warningsAsErrors and deprecationErrors map to -w/-de: verify via DMD compiler docs: https://dlang.org/dmd.html
- gtk-d 3.11.0 is latest: verify via https://code.dlang.org/api/packages/gtk-d/latest
- IOThread uses non-blocking select() loop: verified in iothread.d:399-439.
- Cursor visibility/contrast meets WCAG non-text contrast guidance: verify via WCAG 2.2 SC 1.4.11: https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html

## Roadmap (Phased)
- Phase 1: DUB-first build parity for resources/i18n/schemas/metadata.
- Phase 2: Harden install + uninstall workflows and document prerequisites.
- Phase 3: Formalize backend boundaries and performance benchmarks.
- Phase 4: Feature harvest from other terminals and modernization roadmap.
- Phase 5: Packaging cleanup and Meson deprecation decision point.
