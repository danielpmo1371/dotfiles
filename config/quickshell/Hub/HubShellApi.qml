import QtQuick

// The `shell` object vendored panels reach through `bar.shell` (bar widgets)
// or their own `shell` property (summon-only panels). Mirrors the parts of
// Omarchy's PluginShellApi the panels call; everything routes to shell.qml.
QtObject {
  required property var host

  function summon(id, payloadJson) { return host.summon(String(id || ""), String(payloadJson || "")) }
  function hide(id) { return host.hide(String(id || "")) }
  function toggle(id, payloadJson) { return host.toggle(String(id || ""), String(payloadJson || "")) }
  function isPluginOpen(id) { return host.isPluginOpen(String(id || "")) }
  function updateEntryInline(id, settings) { return host.updateEntryInline(String(id || ""), settings) }

  // Omarchy's bar layout and service registry have no equivalent here.
  function mutateShellConfig(mutator) { return false }
  function serviceFor(id) { return null }
  function firstPartyServiceFor(id) { return null }
}
