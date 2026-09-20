# Plasma Liquid Glass: an iOS-style glass top bar for KDE Plasma 6

![bar](screenshots/bubbles.png)
![one pill, zoomed](screenshots/pill-zoom.png)

The top bar becomes a row of clear glass pills. You see the wallpaper through
them, it bends at each pill's edge like a water drop, and a thin rim catches the
light. Maximize a window and the bar goes flat and solid, out of the way.

## TL;DR

1. Install Panel Colorizer, with its C++ plugin.
2. Build my fork of the Glass KWin effect. Log out and in.
3. Copy two presets, run one script.

Needs `sudo` once, for the effect. Undo is four commands, at the bottom.

Tested on Plasma 6.6.6, Wayland, display scale 2.5.

## Parts

| Part | Job |
| --- | --- |
| [Panel Colorizer](https://github.com/luisbocanegra/plasma-panel-colorizer) | Cuts the panel into pills and tells KWin which areas to blur |
| [kwin-effects-glass, `per-pill-glass` branch](https://github.com/Nael-Nathanael/kwin-effects-glass/tree/per-pill-glass) | Draws the glass: bend, rim, blur |
| `presets/` | Panel Colorizer presets: `Bubbles` (pills) and `Bar` (maximized) |
| `glass-settings.sh` | The Glass effect settings |

The fork is needed. Upstream draws one glass shape around the whole panel, so
only the bar's outer edge bends. The branch draws one shape per pill, and ships
the shader names KWin 6.6 looks for.

## Install

Do these in order.

1. Install Panel Colorizer **with its C++ plugin**. Without the plugin it cannot
   set blur areas and Glass has nothing to draw on. Follow its README.

2. Build and install the Glass fork. Dependencies are listed in its README.

   ```
   git clone -b per-pill-glass https://github.com/Nael-Nathanael/kwin-effects-glass
   cd kwin-effects-glass && mkdir build && cd build
   cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
   make -j"$(nproc)"
   sudo make install
   ```

3. Log out and log in. KWin keeps an already-loaded effect in memory; a new
   build only takes over after re-login.

4. Copy the presets:

   ```
   git clone https://github.com/Nael-Nathanael/plasma-liquid-glass
   mkdir -p ~/.config/panel-colorizer/presets
   cp -r plasma-liquid-glass/presets/* ~/.config/panel-colorizer/presets/
   ```

5. Add the Panel Colorizer widget to your top panel. In its settings:
   - Presets → load `Bubbles`.
   - Preset auto-loading → *Maximized window*: `Bar`, *Normal*: `Bubbles`.

6. Apply the Glass settings:

   ```
   sh plasma-liquid-glass/glass-settings.sh
   ```

The `Bubbles` preset hides the panel's own background (`nativePanel` opacity 0).
Glass needs the wallpaper behind the pills, not a panel fill.

## Check that Glass is drawing

Glass can be listed as loaded and still draw nothing. Prove it with a loud tint:

```
kwriteconfig6 --file kwinrc --group Effect-blurplus --key TintColor '#ccff0000'
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect glass
```

Pills turn red = working. Then remove it:

```
kwriteconfig6 --file kwinrc --group Effect-blurplus --key TintColor --delete
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect glass
```

No red: run `journalctl --user -b | grep -i 'shader\|not linked'`.
`Failed to read shader ... _core.vert` means KWin is running a build without the
branch's shader fix — reinstall, then re-login.

## Tuning

All in `~/.config/kwinrc`, group `[Effect-blurplus]`, or System Settings →
Desktop Effects → Glass.

- `RefractionStrength` — how hard the edge bends. Glass only sees the strip of
  wallpaper under each pill, so very high values streak. 14 stays clean.
- `RefractionEdgeSize` — width of the bending band.
- `RimSpecularScale` — rim brightness, 0–20.
- Pill darkness is in the preset: `widgets.normal.backgroundColor.alpha`.

## After a KWin update

Binary effects break on every KWin update. Rebuild the fork, `sudo make install`,
re-login.

## Undo

```
kwriteconfig6 --file kwinrc --group Plugins --key glassEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect glass
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect blur
```

## Credits

- [4v3ngR/kwin-effects-glass](https://github.com/4v3ngR/kwin-effects-glass) — the Glass effect
- [luisbocanegra/plasma-panel-colorizer](https://github.com/luisbocanegra/plasma-panel-colorizer)

## License

MIT for the files in this repository. The Glass fork stays GPL-3.0.
