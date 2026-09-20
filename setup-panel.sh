#!/bin/sh
# Build the glass top bar, and optionally a dock. Run inside a Plasma 6 session,
# after the presets are copied to ~/.config/panel-colorizer/presets.
#
#   sh setup-panel.sh          top bar only
#   sh setup-panel.sh --dock   top bar and a centered glass dock at the bottom
#
# Safe to re-run: panels that already exist are reused, not duplicated.
#
# CLOCK_FONT_SIZE: the clock does not follow the panel font, it has its own size
# and it shrinks the text to fit the pill. 17 matches a 10pt panel font at display
# scale 2. If the clock looks bigger or smaller than its neighbours, change it:
#   CLOCK_FONT_SIZE=15 sh setup-panel.sh
set -e

DOCK=false
[ "${1:-}" = "--dock" ] && DOCK=true
CLOCK_FONT_SIZE=${CLOCK_FONT_SIZE:-17}
PRESETS="$HOME/.config/panel-colorizer/presets"

if [ "$XDG_CURRENT_DESKTOP" != "KDE" ]; then
    echo "Not in a Plasma session. Log in to Plasma first." >&2
    exit 1
fi
for p in Bubbles Bar; do
    [ -f "$PRESETS/$p/settings.json" ] || { echo "Missing preset $PRESETS/$p. Copy presets/ first." >&2; exit 1; }
done
qdbus=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus) || { echo "No qdbus found." >&2; exit 1; }

"$qdbus" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
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
function colorizer(panel, autoload) {
    var c = find(panel, COLORIZER) || panel.addWidget(COLORIZER);
    c.currentConfigGroup = ['General'];
    c.writeConfig('hideWidget', true);   // else its icon shows up as one more pill
    c.writeConfig('presetAutoloading', JSON.stringify(autoload));
    c.reloadConfig();
}

// Top bar: [clock and tray on the right, your own widgets on the left]
var top = panelAt('top');
if (!top) {
    top = new Panel;
    top.location = 'top';
    top.height = Math.round(gridUnit * 2);
    top.addWidget('org.kde.plasma.panelspacer');
    top.addWidget('org.kde.plasma.systemtray');
    top.addWidget('org.kde.plasma.digitalclock');
}
colorizer(top, {enabled: true, filterByScreen: true, filterByActive: false, trackLastActive: false,
                maximized: PRESETS + '/Bar', normal: PRESETS + '/Bubbles'});

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
print('top bar: panel ' + top.id + '\n');

if ($DOCK) {
    var dock = panelAt('bottom');
    if (!dock) {
        dock = new Panel;
        dock.location = 'bottom';
        dock.height = 56;
        dock.addWidget('org.kde.plasma.icontasks');
    }
    dock.lengthMode = 'fit';
    dock.alignment = 'center';
    dock.floating = true;
    dock.hiding = 'none';
    // The dock stays glass under a maximized window, so no Bar preset here.
    colorizer(dock, {enabled: true, filterByScreen: true, filterByActive: false, trackLastActive: false,
                     normal: PRESETS + '/Bubbles'});
    print('dock: panel ' + dock.id + '\n');
}
"

# Auto-loading only switches presets when the panel state changes, so load once now.
dbus-send --session --type=signal /preset luisbocanegra.panel.colorizer.all.preset string:"$PRESETS/Bubbles"
echo "Bubbles loaded on every Panel Colorizer widget."
