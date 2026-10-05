import QtQuick
import qs.Commons

// One hub tile: the panel's own bar button, scaled up, over a text label.
// The button opens the panel; a click anywhere else on the tile does too.
// A tile with no panel (no `entry`) is an action tile: its glyph stands in for
// the button and a click runs the action through `activate`.
Item {
  id: root

  required property var tile
  required property QtObject bar
  required property string configDir
  required property real iconScale
  property var settings: ({})
  // Called with the tile when an action tile is clicked.
  property var activate: null

  readonly property bool isPanel: !!tile.entry

  readonly property var widget: loader.item
  clip: true

  readonly property bool opened: !!widget && widget.opened === true

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.popups.text
    opacity: root.opened ? 0.16 : (tileHover.hovered ? 0.08 : 0)

    Behavior on opacity {
      NumberAnimation { duration: Style.duration(120) }
    }
  }

  HoverHandler { id: tileHover }

  MouseArea {
    anchors.fill: parent
    onClicked: {
      if (!root.isPanel) {
        if (root.activate) root.activate(root.tile)
      } else if (root.widget && "toggle" in root.widget) {
        root.widget.toggle()
      }
    }
  }

  // The widget lays itself out for a bar slot; the slot keeps that size and
  // the scale makes it read as an icon. PopupCard maps through the scale, so
  // the popup still lines up with the tile.
  Item {
    id: slot
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Style.space(10)
    width: Math.max(Style.bar.iconSlot, loader.item ? loader.item.implicitWidth : 0)
    height: root.bar.barSize
    scale: root.iconScale
    transformOrigin: Item.Top

    Text {
      visible: !root.isPanel
      anchors.centerIn: parent
      text: root.tile.glyph || ""
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.bar.iconFont
    }

    Loader {
      id: loader
      anchors.fill: parent
      asynchronous: false
      active: root.isPanel

      Component.onCompleted: if (root.isPanel) setSource(Util.fileUrl(root.configDir + "/" + root.tile.entry), {
        bar: root.bar,
        moduleName: root.tile.id,
        settings: root.settings
      })

      onLoaded: root.bar.registerWidget(root.tile.id, item)
      onStatusChanged: {
        if (status === Loader.Error) console.warn("hub: cannot load", root.tile.id, root.tile.entry)
      }
    }
  }

  Component.onDestruction: {
    if (loader.item) root.bar.unregisterWidget(root.tile.id, loader.item)
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(8)
    width: parent.width - Style.space(8)
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    text: root.tile.label
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
}
