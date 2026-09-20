#!/bin/sh
# Build the glass top bar, and optionally a dock. Run inside a Plasma 6 session,
# after the presets are copied to ~/.config/panel-colorizer/presets.
#
#   sh setup-panel.sh          top bar only
#   sh setup-panel.sh --dock   top bar and a glass dock at the bottom
#
# Safe to re-run: panels that already exist are reused, not duplicated, and the
# dock's pinned apps are only set when the dock is first made.
#
# CLOCK_FONT_SIZE: the clock does not follow the panel font, it has its own size
# and it shrinks the text to fit the pill. 17 matches a 10pt panel font at display
# scale 2. If the clock looks bigger or smaller than its neighbours, change it:
#   CLOCK_FONT_SIZE=15 sh setup-panel.sh
#
# DOCK_VARIANT: WhiteSurLiquid (dark dot) or WhiteSurLiquid-dark (light dot).
# Picked from your colour scheme when unset.
set -e

DOCK=false
[ "${1:-}" = "--dock" ] && DOCK=true
CLOCK_FONT_SIZE=${CLOCK_FONT_SIZE:-17}
PRESETS="$HOME/.config/panel-colorizer/presets"
WHITESUR=https://raw.githubusercontent.com/vinceliuice/WhiteSur-kde/master/plasma/desktoptheme

if [ "$XDG_CURRENT_DESKTOP" != "KDE" ]; then
    echo "Not in a Plasma session. Log in to Plasma first." >&2
    exit 1
fi
need="Bubbles Bar"
$DOCK && need="$need Dock"
for p in $need; do
    [ -f "$PRESETS/$p/settings.json" ] || { echo "Missing preset $PRESETS/$p. Copy presets/ first." >&2; exit 1; }
done
qdbus=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus) || { echo "No qdbus found." >&2; exit 1; }

# The dock's running-app dot and rounded highlight come from WhiteSur's tasks.svgz.
# A Plasma style that holds only that one file falls back to Breeze for the rest,
# so nothing else on the desktop changes. WhiteSur is GPL-3.0: fetched, not bundled.
if $DOCK; then
    if [ -z "${DOCK_VARIANT:-}" ]; then
        case "$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)" in
            *[Dd]ark*) DOCK_VARIANT=WhiteSurLiquid-dark ;;
            *) DOCK_VARIANT=WhiteSurLiquid ;;
        esac
    fi
    style="$HOME/.local/share/plasma/desktoptheme/WhiteSurDock"
    mkdir -p "$style/widgets"
    curl -fsSL "$WHITESUR/$DOCK_VARIANT/widgets/tasks.svgz" -o "$style/widgets/tasks.svgz"
    cat >"$style/metadata.json" <<'EOF'
{
    "KPlugin": {
        "Authors": [ { "Name": "Vince Liuice (WhiteSur)" } ],
        "Category": "Plasma 6.0 theme",
        "Description": "Breeze, with the task indicators from WhiteSur Liquid",
        "Id": "WhiteSurDock",
        "License": "GPL-3.0",
        "Name": "WhiteSur Dock",
        "Version": "1.0",
        "Website": "https://github.com/vinceliuice/WhiteSur-kde"
    },
    "X-Plasma-API": "5.0"
}
EOF
    plasma-apply-desktoptheme WhiteSurDock >/dev/null
fi

# Prints one "<preset> <panel id> <colorizer widget id>" line per panel.
made=$("$qdbus" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
var COLORIZER = 'luisbocanegra.panel.colorizer';
var PRESETS = '$PRESETS';

function find(panel, type) {
    var hit = null;
    panel.widgets().forEach(function (w) { if (!hit && w.type == type) hit = w; });
    return hit;
}
function panelAt(location) {
    var hit = null;
    panels().forEach(function (p) { if (!hit && p.location == location) hit = p; });
    return hit;
}
function colorizer(panel, preset, autoload) {
    var c = find(panel, COLORIZER) || panel.addWidget(COLORIZER);
    autoload.enabled = true;
    autoload.filterByScreen = true;
    c.currentConfigGroup = ['General'];
    c.writeConfig('hideWidget', true);   // else its icon shows up as one more pill
    c.writeConfig('presetAutoloading', JSON.stringify(autoload));
    c.reloadConfig();
    print(preset + ' ' + panel.id + ' ' + c.id + '\n');
}

var top = panelAt('top');
if (!top) {
    top = new Panel;
    top.location = 'top';
    top.height = Math.round(gridUnit * 2);
    top.addWidget('org.kde.plasma.panelspacer');
    top.addWidget('org.kde.plasma.systemtray');
    top.addWidget('org.kde.plasma.digitalclock');
}
colorizer(top, 'Bubbles', {maximized: PRESETS + '/Bar', normal: PRESETS + '/Bubbles'});

// One line, date beside the time, same size as the other pills.
var clock = find(top, 'org.kde.plasma.digitalclock');
if (clock) {
    clock.currentConfigGroup = ['Appearance'];
    clock.writeConfig('showDate', true);
    clock.writeConfig('dateDisplayFormat', 1);       // beside the time
    clock.writeConfig('dateFormat', 'custom');
    clock.writeConfig('customDateFormat', 'd MMM');
    clock.writeConfig('use24hFormat', 2);            // 0 = 12h, 1 = locale, 2 = 24h
    clock.writeConfig('autoFontAndSize', false);
    clock.writeConfig('fontSize', $CLOCK_FONT_SIZE);
    clock.reloadConfig();
}

if ($DOCK) {
    var dock = panelAt('bottom');
    if (!dock) {
        dock = new Panel;
        dock.location = 'bottom';
        var tasks = dock.addWidget('org.kde.plasma.icontasks');
        tasks.currentConfigGroup = ['General'];
        tasks.writeConfig('launchers', ['preferred://filemanager', 'preferred://browser', 'applications:systemsettings.desktop']);
        tasks.reloadConfig();
    }
    // Same shape as the WhiteSur layout: as wide as its icons, out of a window's way.
    dock.height = 64;
    dock.lengthMode = 'fit';
    dock.alignment = 'center';
    dock.floating = true;
    dock.hiding = 'dodgewindows';
    // One slab of glass, maximized window or not: no Bar preset here.
    colorizer(dock, 'Dock', {normal: PRESETS + '/Dock'});
}
")

# Auto-loading only switches presets when the panel state changes, so load once now.
# A widget added a moment ago needs a second before its D-Bus name is up.
echo "$made" | while read -r preset panel widget; do
    [ -n "$widget" ] || continue
    name="luisbocanegra.panel.colorizer.c$panel.w$widget"
    tries=0
    until "$qdbus" "$name" /preset preset "$PRESETS/$preset" >/dev/null 2>&1; do
        tries=$((tries + 1))
        [ "$tries" -lt 10 ] || { echo "panel $panel: could not reach $name, load $preset by hand" >&2; break; }
        sleep 1
    done
    if [ "$tries" -lt 10 ]; then echo "panel $panel: $preset loaded"; fi
done
