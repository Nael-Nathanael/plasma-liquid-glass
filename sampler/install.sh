#!/bin/sh
# Build and install glassbar-sampler: the top bar takes the colour of the maximized
# window's title bar. Run inside the Plasma session, after setup-panel.sh.
# No sudo: everything goes under ~/.local and ~/.config.
#
# Needs cmake, a C++ compiler and the Qt 6 base headers (Ubuntu: qt6-base-dev).
# Run it again after the top panel is rebuilt: the panel's ids are in the Exec line.
set -e
cd "$(dirname "$0")"

PRESET="$HOME/.config/panel-colorizer/presets/Bar"
BIN="$HOME/.local/bin/glassbar-sampler"
DESKTOP="$HOME/.local/share/applications/io.github.naelnathanael.glassbar-sampler.desktop"

[ -f "$PRESET/settings.json" ] || { echo "Missing $PRESET. Copy presets/ and run setup-panel.sh first." >&2; exit 1; }
qdbus=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus) || { echo "No qdbus found." >&2; exit 1; }

# Which Panel Colorizer to talk to: the one on the top panel.
ids=$("$qdbus" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
panels().forEach(function (p) {
    if (p.location != 'top') return;
    p.widgets().forEach(function (w) { if (w.type == 'luisbocanegra.panel.colorizer') print('c' + p.id + '.w' + w.id); });
});")
[ -n "$ids" ] || { echo "No Panel Colorizer on a top panel. Run setup-panel.sh first." >&2; exit 1; }
colorizer="luisbocanegra.panel.colorizer.$(echo "$ids" | head -n 1)"

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build build >/dev/null
# Not pkill -x: the name is 16 characters and the kernel keeps 15.
pkill -f "^$BIN " 2>/dev/null || true
install -Dm755 build/glassbar-sampler "$BIN"

# KWin checks this file before it lets the program read the screen: the Exec line
# must start with the program's own path. The same file starts it at login.
mkdir -p "$(dirname "$DESKTOP")" "$HOME/.config/autostart"
cat >"$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Glass Bar Sampler
Comment=Colours the top bar like the maximized window's title bar
Exec=$BIN $colorizer $PRESET
NoDisplay=true
X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2
EOF
ln -sf "$DESKTOP" "$HOME/.config/autostart/"
kbuildsycoca6 >/dev/null 2>&1 || true

if kpackagetool6 -t KWin/Script -s glassbar-sampler >/dev/null 2>&1; then
    kpackagetool6 -t KWin/Script -u kwin-script >/dev/null
else
    kpackagetool6 -t KWin/Script -i kwin-script >/dev/null
fi
kwriteconfig6 --file kwinrc --group Plugins --key glassbar-samplerEnabled true
"$qdbus" org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript glassbar-sampler >/dev/null 2>&1 || true

setsid "$BIN" "$colorizer" "$PRESET" >/dev/null 2>&1 &
"$qdbus" org.kde.KWin /KWin reconfigure

echo "glassbar-sampler running for $colorizer. Maximize a window to see it."
