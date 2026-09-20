#!/bin/sh
# Write the Glass effect settings, then swap stock Blur for Glass.
set -e

k() { kwriteconfig6 --file kwinrc --group Effect-blurplus --key "$1" "$2"; }

# Keep 0: a dock radius clips the whole panel window and rounds a full-width bar.
# Pills take their roundness from their own shape.
k DockCornerRadius 0
k DockBlurStrength 1

k PhysicallyBasedRefraction true
k RefractionStrength 14
k RefractionEdgeSize 1.4
k RefractionRGBFringing 4

# EdgeLighting blows small pills out to solid white. The specular rim does not.
k EdgeLighting false
k RimSpecular true
k RimWidth 12
k RimSpecularScale 8

kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key glassEnabled true

qdbus=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus) || {
    echo "Settings written. No qdbus found: log out and in to load Glass." >&2
    exit 0
}
"$qdbus" org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect blur
"$qdbus" org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect glass
