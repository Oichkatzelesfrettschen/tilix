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
- DUB emits a warning about warningsAsErrors needing buildRequirements support.
- .claude directory permissions cause noisy git status warnings.

## Sanity Check
- DUB build and tests pass with the verified layout tests enabled.
- DUB now runs resource preparation before builds.
- Install uses staged artifacts to avoid polluting the source tree.

## Testable Hypotheses and Validation Notes
- Tilix is GTK3 + VTE3 based: verified via dub.json dependencies.
- DUB supports preBuildCommands/postBuildCommands: verified in dub-docs.
- warningsAsErrors and deprecationErrors map to -w/-de: verified in dub-docs
  and dmd.html.
- targetType=none is supported: verified in dub-docs target_types.
- gtk-d 3.11.0 is latest: validated via `dub search gtk-d`.

## Roadmap (Phased)
- Phase 1: DUB-first build parity for resources/i18n/schemas/metadata.
- Phase 2: Harden install + uninstall workflows and document prerequisites.
- Phase 3: Formalize backend boundaries and performance benchmarks.
- Phase 4: Feature harvest from other terminals and modernization roadmap.
- Phase 5: Packaging cleanup and Meson deprecation decision point.
