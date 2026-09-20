// Report the frame of the active window to glassbar-sampler whenever that window
// fills the maximize area. KWin scripts cannot read pixels; the sampler can.
const SERVICE = "io.github.naelnathanael.GlassBar";

function report() {
    const w = workspace.activeWindow;
    if (!w || !w.normalWindow || w.fullScreen)
        return;
    const area = workspace.clientArea(KWin.MaximizeArea, w);
    const g = w.frameGeometry;
    const same = (a, b) => Math.abs(a - b) < 2;
    if (!same(g.x, area.x) || !same(g.y, area.y) || !same(g.width, area.width) || !same(g.height, area.height))
        return;
    callDBus(SERVICE, "/", SERVICE, "sample", `${Math.round(g.x)} ${Math.round(g.y)} ${Math.round(g.width)}`);
}

// maximizedChanged can fire before the frame has its new size, so look again when
// the frame changes. report() returns at once unless the frame fills the area.
function watch(w) {
    w.maximizedChanged.connect(report);
    w.frameGeometryChanged.connect(report);
}

workspace.windowList().forEach(watch);
workspace.windowAdded.connect(watch);
workspace.windowActivated.connect(report);
report();
