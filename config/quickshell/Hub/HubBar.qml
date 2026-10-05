import QtQuick
import qs.Commons

// Stand-in for Omarchy's Bar, the `bar` object every vendored panel reads.
// The panels were written as bar widgets: they paint their own button from
// these colours and sizes, anchor their popup beside it, and coordinate with
// the host so only one popup is open at a time. The hub hosts them as grid
// tiles instead of bar slots, so this object carries just that contract.
//
// `position` drives where PopupCard opens relative to the tile. The hub sits
// on the right edge of the screen, so popups open to its left. `vertical`
// stays false so widgets keep their compact horizontal look inside a tile.
Item {
  id: root

  property var shell: null
  property string position: "right"
  readonly property bool vertical: false
  readonly property int barSize: Style.bar.sizeHorizontal

  property string fontFamily: Style.font.family
  property color foreground: Color.bar.text
  property color barForeground: Color.bar.text
  property color background: Color.bar.background
  property color urgent: Color.bar.active
  property bool transparent: false
  property bool foregroundAnimationEnabled: true
  property bool centerHoverRevealSuppressed: false

  // The one popup currently open, or null. Opening another closes it first,
  // the same rule Omarchy's bar applies.
  property var activePopout: null
  property var clickTargets: []

  // moduleName -> live widget, filled by the hub tiles.
  property var widgets: ({})

  signal popoutOpened(var owner)
  signal popoutReleased(var owner)

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
    popoutOpened(owner)
  }

  function releasePopout(owner) {
    if (activePopout !== owner) return
    activePopout = null
    popoutReleased(owner)
  }

  function closeActivePopout() {
    if (!activePopout) return false
    var owner = activePopout
    if ("close" in owner) owner.close()
    releasePopout(owner)
    return true
  }

  function registerWidget(name, widget) {
    var next = {}
    for (var key in widgets) next[key] = widgets[key]
    next[name] = widget
    widgets = next
  }

  function unregisterWidget(name, widget) {
    if (widgets[name] !== widget) return
    var next = {}
    for (var key in widgets) if (key !== name) next[key] = widgets[key]
    widgets = next
  }

  function moduleWidgets(name) {
    var widget = widgets[String(name || "")]
    return widget ? [widget] : []
  }

  // Panels call this for their left/right arrow keys. The hub has no bar
  // order to walk, so the key is left to the panel.
  function switchPanelFrom(owner, direction) {
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    centerHoverRevealSuppressed = !!value
  }

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    clickTargets = clickTargets.concat([target])
  }

  function unregisterClickTarget(target) {
    clickTargets = clickTargets.filter(function(item) { return item !== target })
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && target.QsWindow && target.QsWindow.window === window
  }

  // Tiles carry a text label, so the bar's hover tooltips are not needed.
  function showTooltip(target, text) {}
  function hideTooltip(target) {}

  function run(command) {
    if (command) Util.execDetached(command)
  }
}
