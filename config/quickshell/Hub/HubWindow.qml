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
    Keys.onEscapePressed: {
      if (!root.bar.closeActivePopout()) root.hide()
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

    Grid {
      id: grid
      anchors.top: title.bottom
      anchors.left: parent.left
      anchors.topMargin: Style.space(10)
      anchors.leftMargin: root.cardPadding
      columns: root.columns
      spacing: Style.space(6)

      Repeater {
        model: root.visibleTiles

        delegate: HubTile {
          required property var modelData
          width: root.tileWidth
          height: root.tileHeight
          tile: modelData
          bar: root.bar
          configDir: root.configDir
          iconScale: root.tileScale
          settings: root.mergedSettings(modelData)
          activate: root.runAction
        }
      }
    }
  }
}
