#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

DATA_DIR="$ROOT_DIR/data"
PO_DIR="$ROOT_DIR/po"
RES_DIR="$DATA_DIR/resources"
BUILD_DIR="$ROOT_DIR/build/dub"
SCHEMA_DIR="$BUILD_DIR/schemas"

RESOURCE_OUT="$BUILD_DIR/tilix.gresource"
DESKTOP_OUT="$BUILD_DIR/com.gexperts.Tilix.desktop"
APPDATA_OUT="$BUILD_DIR/com.gexperts.Tilix.appdata.xml"
APPDATA_TEMPLATE="$DATA_DIR/metainfo/com.gexperts.Tilix.appdata.xml.in"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

require_cmd glib-compile-resources
require_cmd glib-compile-schemas
require_cmd msgfmt
require_cmd desktop-file-validate

filter_glycin_warnings() {
    local in_file="$1"
    local filtered="${in_file}.filtered"
    grep -v "WARNING: Glycin running without sandbox." "$in_file" > "$filtered" || true
    if [ -s "$filtered" ]; then
        cat "$filtered" >&2
        exit 1
    fi
}

mkdir -p "$BUILD_DIR"

echo "Preparing resources in $BUILD_DIR"

GLIB_RES_STDERR="$BUILD_DIR/glib-compile-resources.stderr"
glib-compile-resources \
    "$RES_DIR/tilix.gresource.xml" \
    --sourcedir="$RES_DIR" \
    --target="$RESOURCE_OUT" \
    2>"$GLIB_RES_STDERR"
filter_glycin_warnings "$GLIB_RES_STDERR"

mkdir -p "$SCHEMA_DIR"
cp "$DATA_DIR/gsettings/com.gexperts.Tilix.gschema.xml" "$SCHEMA_DIR/"
glib-compile-schemas "$SCHEMA_DIR"

if [ -d "$PO_DIR" ]; then
    find "$PO_DIR" -name "*.po" -printf "%f\n" | sed "s/\.po//g" | sort > "$PO_DIR/LINGUAS"
fi

if msgfmt --desktop --template="$DATA_DIR/pkg/desktop/com.gexperts.Tilix.desktop.in" -d "$PO_DIR" -o "$DESKTOP_OUT"; then
    :
else
    echo "Note: localizing the desktop file requires newer gettext, copying template instead." >&2
    cp "$DATA_DIR/pkg/desktop/com.gexperts.Tilix.desktop.in" "$DESKTOP_OUT"
fi

desktop-file-validate "$DESKTOP_OUT"

if msgfmt --xml --template="$APPDATA_TEMPLATE" -d "$PO_DIR" -o "$APPDATA_OUT"; then
    :
else
    echo "Note: localizing appdata requires xgettext 0.19.7+, copying template instead." >&2
    cp "$APPDATA_TEMPLATE" "$APPDATA_OUT"
fi

if command -v appstreamcli >/dev/null 2>&1; then
    APPSTREAM_NEWS_STDERR="$BUILD_DIR/appstream-news.stderr"
    APPSTREAM_STDERR="$BUILD_DIR/appstream.stderr"
    APPSTREAM_REPORT="$BUILD_DIR/appstream-validation.yaml"

    if appstreamcli news-to-metainfo --limit=6 "$ROOT_DIR/NEWS" "$APPDATA_OUT" "$APPDATA_OUT.tmp" \
        >/dev/null 2>"$APPSTREAM_NEWS_STDERR"; then
        filter_glycin_warnings "$APPSTREAM_NEWS_STDERR"
        mv "$APPDATA_OUT.tmp" "$APPDATA_OUT"
    fi

    appstreamcli validate --no-net --format yaml \
        "$APPDATA_OUT" >"$APPSTREAM_REPORT" 2>"$APPSTREAM_STDERR"

    filter_glycin_warnings "$APPSTREAM_STDERR"

    python - "$APPSTREAM_REPORT" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, "r", encoding="utf-8").read()

# Parse YAML-like output with regex instead of ast.literal_eval
# Look for severity: <level> patterns
severity_pattern = re.compile(r'severity:\s*(\w+)')
tag_pattern = re.compile(r'tag:\s*([\w-]+)')

severities = severity_pattern.findall(text)
tags = tag_pattern.findall(text)

allowed_pedantic_tags = {"cid-contains-uppercase-letter"}
bad = []

for sev, tag in zip(severities, tags):
    if sev in ("warning", "error"):
        bad.append((sev, tag))
    elif sev == "pedantic" and tag not in allowed_pedantic_tags:
        bad.append((sev, tag))

if bad:
    for sev, tag in bad:
        print(f"AppStream validation issue: {sev} {tag}", file=sys.stderr)
    sys.exit(1)
PY
fi
