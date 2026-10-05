import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The hub: a card on the right edge of the focused screen holding a grid of
// tiles, one per panel in tiles.json. Each tile hosts the panel's own bar
// button, scaled up, with a label under it; the panel's popup opens to the
// left of the card. Esc or a click outside closes the open popup, then the hub.
//
// Keys: h/j/k/l or the arrows move the cursor, Enter/Space/o opens the tile,
// q or Esc closes. Inside a panel its own keys apply (j/k/h/l too); Tab and
// Shift+Tab there move to the next or previous panel tile.
PanelWindow {
  id: root

  required property QtObject bar
  required property string configDir
  required property var settingsFor

  readonly property int columns: 3
  readonly property real tileScale: 1.6
  readonly property int tileWidth: Style.space(96)
  readonly property int tileHeight: Style.space(84)
  readonly property int cardPadding: Style.space(14)

  property var tiles: []
  // Index into visibleTiles of the tile the keyboard cursor is on.
  property int cursor: 0
  property var availableCommands: ({})
  property bool commandsChecked: false
  // Empty until the command check is back, so each tile is built once: a
  // rebuilt tile would briefly hold its panel's IPC target twice.
  readonly property var visibleTiles: !commandsChecked ? [] : tiles.filter(function(tile) {
    return !tile.requires || root.availableCommands[tile.requires] === true
  })

  // tiles.json defaults, overridden by whatever the panel saved itself.
  function mergedSettings(tile) {
    var merged = {}
    var defaults = tile.settings || {}
    var saved = root.settingsFor(tile.id)
    for (var key in defaults) merged[key] = defaults[key]
    for (var savedKey in saved) merged[savedKey] = saved[savedKey]
    return merged
  }

  // Action tiles: hide the hub, then summon a plugin or run a command.
  function runAction(tile) {
    hide()
    if (tile.summon) bar.shell.summon(tile.summon, JSON.stringify(tile.payload || {}))
    else if (tile.exec) Util.execArgv(tile.exec)
  }

  // h/l walk the tiles in reading order; j/k move a row and stay put when
  // no tile is there.
  function moveCursor(dx, dy) {
    var count = visibleTiles.length
    if (count === 0) return
    if (dx !== 0) {
      cursor = Math.max(0, Math.min(count - 1, cursor + dx))
    } else {
      var next = cursor + dy * columns
      if (next >= 0 && next < count) cursor = next
    }
  }

  function activateCursor() {
    var item = tileRepeater.itemAt(cursor)
    if (item) item.trigger()
  }

  // Tab inside a panel: open the next panel tile in grid order, wrapping
  // past the end and skipping action tiles.
  function switchPanelFrom(owner, direction) {
    var count = visibleTiles.length
    var from = -1
    for (var i = 0; i < count; i++) {
      if (bar.widgets[visibleTiles[i].id] === owner) { from = i; break }
    }
    if (from === -1) return false
    for (var step = 1; step < count; step++) {
      var index = ((from + step * direction) % count + count) % count
      var widget = bar.widgets[visibleTiles[index].id]
      if (visibleTiles[index].entry && widget && "open" in widget) {
        cursor = index
        widget.open()
        return true
      }
    }
    return false
  }

  function show() { visible = true }
  function hide() {
    bar.closeActivePopout()
    visible = false
  }
  function toggle() { visible ? hide() : show() }

  visible: false
  color: "transparent"
  screen: Quickshell.screens.find(function(s) {
    return Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name
  }) || Quickshell.screens[0]

  anchors.top: true
  anchors.right: true
  margins.top: Style.gapsOut * 2
  margins.right: Style.gapsOut * 2
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "omarchy-hub"
  WlrLayershell.layer: WlrLayer.Overlay
  // Keys only while no panel popup is open; an open KeyboardPanel takes them.
  WlrLayershell.keyboardFocus: visible && !bar.activePopout ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  implicitWidth: grid.implicitWidth + cardPadding * 2
  implicitHeight: title.implicitHeight + Style.space(10) + grid.implicitHeight + cardPadding * 2

  HyprlandFocusGrab {
    active: root.visible && !root.bar.activePopout
    windows: [root]
    onCleared: root.hide()
  }

  FileView {
    path: root.configDir + "/Hub/tiles.json"
    printErrors: true
    onLoaded: {
      root.tiles = JSON.parse(text())
      var needed = root.tiles.map(function(tile) { return tile.requires }).filter(function(cmd) { return !!cmd })
      commandCheck.command = ["bash", "-c", 'for c in "$@"; do command -v "$c" >/dev/null && echo "$c"; done; exit 0', "bash"].concat(needed)
      commandCheck.running = true
    }
  }

  Process {
    id: commandCheck
    stdout: StdioCollector {
      onStreamFinished: {
        var found = {}
        text.split("\n").forEach(function(cmd) { if (cmd) found[cmd] = true })
        root.availableCommands = found
        root.commandsChecked = true
      }
    }
  }

  BorderSurface {
    id: card
    anchors.fill: parent
    color: Color.popups.background
    borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(2)))
    radius: Style.cornerRadius

    focus: true
    Keys.onPressed: function(event) {
      if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
      if (event.key === Qt.Key_Escape) {
        if (!root.bar.closeActivePopout()) root.hide()
      } else if (event.text === "q") {
        root.hide()
      } else if (event.key === Qt.Key_Left || event.text === "h") {
        root.moveCursor(-1, 0)
      } else if (event.key === Qt.Key_Right || event.text === "l") {
        root.moveCursor(1, 0)
      } else if (event.key === Qt.Key_Up || event.text === "k") {
        root.moveCursor(0, -1)
      } else if (event.key === Qt.Key_Down || event.text === "j") {
        root.moveCursor(0, 1)
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                 || event.key === Qt.Key_Space || event.text === "o") {
        root.activateCursor()
      } else {
        return
      }
      event.accepted = true
    }

    Text {
      id: title
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.topMargin: root.cardPadding
      anchors.leftMargin: root.cardPadding
      text: "Control hub"
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      anchors.verticalCenter: title.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: root.cardPadding
      text: "hjkl  ⏎ open  q close"
      color: Color.popups.text
      opacity: 0.55
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Grid {
      id: grid
      anchors.top: title.bottom
      anchors.left: parent.left
      anchors.topMargin: Style.space(10)
      anchors.leftMargin: root.cardPadding
      columns: root.columns
      spacing: Style.space(6)

      Repeater {
        id: tileRepeater
        model: root.visibleTiles

        delegate: HubTile {
          required property var modelData
          required property int index
          width: root.tileWidth
          height: root.tileHeight
          tile: modelData
          bar: root.bar
          configDir: root.configDir
          iconScale: root.tileScale
          settings: root.mergedSettings(modelData)
          activate: root.runAction
          selected: root.cursor === index
          onHoverEntered: root.cursor = index
        }
      }
    }
  }
}
