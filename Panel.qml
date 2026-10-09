import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar popup host. The vault UI lives in VaultContent.qml, shared with
// VaultWindow.qml; this file owns only the popup lifecycle. A layershell
// popup dismisses on focus loss, which loses a half-typed add form the
// moment you go fetch the value from another app — press o (or right-click
// the bar icon) to reopen the same content as a real window instead.
Panel {
  id: root
  moduleName: "skh.agent-vault"
  ipcTarget: "skh.agent-vault"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function open() {
    root.controller.show()
    content.armHover()
    content.refresh()
  }
  function openFromHotkey() { open() }
  function close() {
    content.adding = false
    root.controller.hide()
  }
  function toggle() { root.opened ? close() : open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: content.keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    VaultContent {
      id: content
      width: parent.width
      height: parent.height
      bar: root.bar
      hostWidget: root.hostWidget

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // Hand the session over to the window, so the popup is never the thing
      // standing between you and the clipboard.
      onWindowRequested: {
        root.close()
        if (root.hostWidget && root.hostWidget.openWindow) root.hostWidget.openWindow()
      }
    }
  }
}
