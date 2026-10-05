//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Hub"

// Control hub: a grid of Omarchy's panels on the right edge of the screen,
// without Omarchy's bar. Launched by util-scripts/hub-shell, which sets
// OMARCHY_PATH (vendored helpers and plugin data) and puts the helpers on PATH.
//
//   qs ipc -p "$OMARCHY_PATH/shell" call hub toggle
//   qs ipc -p "$OMARCHY_PATH/shell" call hub open omarchy.network
//
// The vendored panels also answer their own targets (omarchy.network etc.),
// and `omarchy-shell shell summon <id> <json>` reaches the summon-only panels
// (speed test, Wi-Fi QR, disk speed test, image picker).
ShellRoot {
  id: root

  readonly property string configDir: Quickshell.shellDir
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy-hub"

  // moduleName -> settings object the panel saved through updateEntryInline.
  property var panelSettings: ({})
  property bool settingsLoaded: false

  // Summon-only plugins: id -> { entry, manifest }. They build their own
  // windows and are kept loaded, so a summon reaches them instantly.
  readonly property var summonPlugins: ({
    "omarchy.speedtest": "plugins/panels/speedtest",
    "omarchy.disk-speedtest": "plugins/panels/disk-speedtest",
    "omarchy.wifiqr": "plugins/panels/wifiqr",
    "omarchy.image-picker": "plugins/image-picker"
  })
  property var summonItems: ({})

  function settingsFor(name) {
    var value = panelSettings[name]
    return value && typeof value === "object" ? value : ({})
  }

  function updateEntryInline(name, settings) {
    var next = {}
    for (var key in panelSettings) next[key] = panelSettings[key]
    next[String(name)] = settings || {}
    panelSettings = next
    settingsFile.setText(JSON.stringify(panelSettings, null, 2) + "\n")
    return true
  }

  function summon(id, payloadJson) {
    var tileWidget = hubBar.widgets[id]
    if (tileWidget) {
      hub.show()
      if ("open" in tileWidget) tileWidget.open()
      return true
    }
    var item = summonItems[id]
    if (!item) {
      console.warn("summon: unknown plugin", id)
      return false
    }
    item.open(payloadJson || "")
    return true
  }

  function hide(id) {
    var tileWidget = hubBar.widgets[id]
    if (tileWidget && "close" in tileWidget) {
      tileWidget.close()
      return true
    }
    var item = summonItems[id]
    if (item && "close" in item) item.close()
    return !!item
  }

  function toggle(id, payloadJson) {
    var tileWidget = hubBar.widgets[id]
    if (tileWidget && tileWidget.opened) return hide(id)
    var item = summonItems[id]
    if (item && item.opened) return hide(id)
    return summon(id, payloadJson)
  }

  function isPluginOpen(id) {
    var target = hubBar.widgets[id] || summonItems[id]
    return !!(target && target.opened)
  }

  HubShellApi {
    id: shellApi
    host: root
  }

  HubBar {
    id: hubBar
    shell: shellApi
    switchPanelHandler: hub.switchPanelFrom
  }

  HubWindow {
    id: hub
    bar: hubBar
    configDir: root.configDir
    settingsFor: root.settingsFor
  }

  // Summon-only plugins, mounted at startup like Omarchy's keepLoaded ones.
  Instantiator {
    model: Object.keys(root.summonPlugins)

    delegate: QtObject {
      id: summonEntry
      required property string modelData
      readonly property string dir: root.configDir + "/" + root.summonPlugins[modelData]

      property FileView manifestFile: FileView {
        path: summonEntry.dir + "/manifest.json"
        printErrors: true
        onLoaded: {
          var manifest = JSON.parse(text())
          var entry = manifest.entryPoints.panel || manifest.entryPoints.overlay
          var component = Qt.createComponent(Util.fileUrl(summonEntry.dir + "/" + entry))
          if (component.status === Component.Error) {
            console.warn("hub: cannot load", summonEntry.modelData, component.errorString())
            return
          }
          var item = component.createObject(root)
          // Summon-only panels take the shell API and their manifest; the
          // image picker takes neither.
          if ("shell" in item) item.shell = shellApi
          if ("manifest" in item) item.manifest = manifest
          var next = {}
          for (var key in root.summonItems) next[key] = root.summonItems[key]
          next[summonEntry.modelData] = item
          root.summonItems = next
        }
      }
    }
  }

  FileView {
    id: settingsFile
    path: root.stateDir + "/settings.json"
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try { root.panelSettings = JSON.parse(text()) || {} } catch (e) { root.panelSettings = {} }
      root.settingsLoaded = true
    }
    onLoadFailed: root.settingsLoaded = true
    onSaveFailed: Quickshell.execDetached(["mkdir", "-p", root.stateDir])
  }

  // Runtime theme switches push the new palette here, as Omarchy's
  // omarchy-theme-set does; colors.toml and shell.toml arrive base64-encoded.
  IpcHandler {
    target: "shell"

    function applyTheme(colorsB64: string, shellB64: string): void {
      if (colorsB64) Color.loadColors(Util.decodeBase64(colorsB64))
      Color.loadShell(shellB64 ? Util.decodeBase64(shellB64) : "")
    }

    function summon(id: string, payloadJson: string): string {
      return root.summon(id, payloadJson) ? "ok" : "unknown"
    }

    function hide(id: string): void { root.hide(id) }
    function toggle(id: string, payloadJson: string): void { root.toggle(id, payloadJson) }
    function ping(): string { return "pong" }
  }

  IpcHandler {
    target: "hub"

    function toggle(): void { hub.toggle() }
    function show(): void { hub.show() }
    function hide(): void { hub.hide() }
    function open(id: string): void { root.summon(id, "{}") }
  }
}
