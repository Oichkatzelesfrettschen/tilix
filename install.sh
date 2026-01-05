#!/usr/bin/env sh
# exit on first error
set -o errexit

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Determine PREFIX.
if [ -z "$1" ]; then
    if [ -z "$PREFIX" ]; then
        PREFIX='/usr'
    fi
else
    PREFIX="$1"
fi
export PREFIX

if [ "$PREFIX" = "/usr" ] && [ "$(id -u)" != "0" ]; then
    # Make sure only root can run our script
    echo "This script must be run as root" 1>&2
    exit 1
fi

if [ ! -f tilix ]; then
    echo "The tilix executable does not exist, please run 'dub build --build=release' before using this script"
    exit 1
fi

# Check availability of required commands
COMMANDS="install glib-compile-schemas glib-compile-resources msgfmt desktop-file-validate gtk-update-icon-cache"
if [ "$PREFIX" = '/usr' ] || [ "$PREFIX" = "/usr/local" ]; then
    COMMANDS="$COMMANDS xdg-desktop-menu"
fi
PACKAGES="coreutils glib2 gettext desktop-file-utils gtk-update-icon-cache xdg-utils"
i=0
for COMMAND in $COMMANDS; do
    type $COMMAND >/dev/null 2>&1 || {
        j=0
        for PACKAGE in $PACKAGES; do
            if [ $i = $j ]; then
                break
            fi
            j=$(( $j + 1 ))
        done
        echo "Your system is missing command $COMMAND, please install $PACKAGE"
        exit 1
    }
    i=$(( $i + 1 ))
done

echo "Installing to prefix $PREFIX"

# Prepare resources and localized metadata in build staging.
PREP_SCRIPT="$SCRIPT_DIR/scripts/dub/prepare-resources.sh"
if [ ! -x "$PREP_SCRIPT" ]; then
    echo "Missing resource prep script: $PREP_SCRIPT" 1>&2
    exit 1
fi

$PREP_SCRIPT

BUILD_DIR="$SCRIPT_DIR/build/dub"
RESOURCE_OUT="$BUILD_DIR/tilix.gresource"
DESKTOP_OUT="$BUILD_DIR/com.gexperts.Tilix.desktop"
APPDATA_OUT="$BUILD_DIR/com.gexperts.Tilix.appdata.xml"
DBUS_OUT="$BUILD_DIR/com.gexperts.Tilix.service"

if [ ! -f "$RESOURCE_OUT" ]; then
    echo "Resource bundle not found: $RESOURCE_OUT" 1>&2
    exit 1
fi
if [ ! -f "$DESKTOP_OUT" ]; then
    echo "Desktop file not found: $DESKTOP_OUT" 1>&2
    exit 1
fi
if [ ! -f "$APPDATA_OUT" ]; then
    echo "Appdata file not found: $APPDATA_OUT" 1>&2
    exit 1
fi

# Copy and compile schema
echo "Copying and compiling schema..."
install -Dm 644 data/gsettings/com.gexperts.Tilix.gschema.xml -t "$PREFIX/share/glib-2.0/schemas/"
glib-compile-schemas $PREFIX/share/glib-2.0/schemas/

export TILIX_SHARE="$PREFIX/share/tilix"

# Copy compiled resources
echo "Copying resources..."
install -Dm 644 "$RESOURCE_OUT" -t "$TILIX_SHARE/resources/"

# Copy shell integration script
echo "Copying scripts..."
install -Dm 755 data/scripts/* -t "$TILIX_SHARE/scripts/"

# Copy color schemes
echo "Copying color schemes..."
install -Dm 644 data/schemes/* -t "$TILIX_SHARE/schemes/"

# Compile po files
echo "Copying and installing localization files"
for f in po/*.po; do
    echo "Processing $f"
    LOCALE=$(basename "$f" .po)
    msgfmt $f -o "$LOCALE.mo"
    install -Dm 644 "$LOCALE.mo" "$PREFIX/share/locale/$LOCALE/LC_MESSAGES/tilix.mo"
    rm -f "$LOCALE.mo"
done

desktop-file-validate "$DESKTOP_OUT"

# Copying Nautilus extension
echo "Copying Nautilus extension"
install -Dm 644 data/nautilus/open-tilix.py -t "$PREFIX/share/nautilus-python/extensions/"

# Copy D-Bus service descriptor
sed "s|@bindir@|$PREFIX/bin|g" data/dbus/com.gexperts.Tilix.service.in > "$DBUS_OUT"
install -Dm 644 "$DBUS_OUT" -t "$PREFIX/share/dbus-1/services/"

# Copy man page
. $(dirname $(realpath "$0"))/data/scripts/install-man-pages.sh

# Copy Icons
cd data/icons/hicolor

find . -type f | while read f; do
    install -Dm 644 "$f" "$PREFIX/share/icons/hicolor/$f"
done

cd ../../..

# Copy executable, desktop and appdata file
install -Dm 755 tilix -t "$PREFIX/bin/"

install -Dm 644 "$DESKTOP_OUT" -t "$PREFIX/share/applications/"
install -Dm 644 "$APPDATA_OUT" -t "$PREFIX/share/metainfo/"

# Update icon cache if Prefix is /usr
if [ "$PREFIX" = '/usr' ] || [ "$PREFIX" = "/usr/local" ]; then
    echo "Updating desktop file cache"
    xdg-desktop-menu forceupdate --mode system

    echo "Updating icon cache"
    gtk-update-icon-cache -f "$PREFIX/share/icons/hicolor/"
fi
