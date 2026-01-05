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

mkdir -p "$BUILD_DIR"

echo "Preparing resources in $BUILD_DIR"

glib-compile-resources \
    "$RES_DIR/tilix.gresource.xml" \
    --sourcedir="$RES_DIR" \
    --target="$RESOURCE_OUT"

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

if msgfmt --xml --template="$DATA_DIR/metainfo/com.gexperts.Tilix.appdata.xml.in" -d "$PO_DIR" -o "$APPDATA_OUT"; then
    :
else
    echo "Note: localizing appdata requires xgettext 0.19.7+, copying template instead." >&2
    cp "$DATA_DIR/metainfo/com.gexperts.Tilix.appdata.xml.in" "$APPDATA_OUT"
fi

if command -v appstreamcli >/dev/null 2>&1; then
    appstreamcli validate --no-net "$APPDATA_OUT"
fi
