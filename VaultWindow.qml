import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Full-application surface: an ordinary desktop window (alt-tab-able, stays
// put when focus moves elsewhere). Use this while adding a secret you must
// first copy out of another app — the bar popup is a layershell surface that
// dismisses on focus loss and would discard the half-typed form.
//
// This is the plugin's `panel` entry point, so the SHELL mounts it (a plugin
// may not host its own window from a bar-widget Loader). Summon with:
//   omarchy-shell shell summon skh.agent-vault "{}"
// The root is an Item holding a FloatingWindow, and exposes the open/close
// lifecycle the shell's panel loader calls — same contract as dev-gallery.
Item {
  id: root

  // ---- host injections ----------------------------------------------------
  property var shell: null
  property QtObject bar: null
  property var hostWidget: null

  // ---- plugin lifecycle ---------------------------------------------------
  property bool closingFromHost: false

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    content.refresh()
    Qt.callLater(function() { content.keyCatcher.forceActiveFocus() })
  }

  // Host-initiated close (`shell hide`): flip visibility without telling the
  // host back, it already knows.
  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  // User-initiated close (Esc, window close button): tell the shell so its
  // openPanelIds map stays consistent and the next toggle works.
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("skh.agent-vault")
    else window.visible = false
  }

  FloatingWindow {
    id: window

    title: "Agent Vault"
    // The theme background can carry alpha, which a layershell popup renders
    // over a blurred backdrop \u2014 in a plain window it just shows the wallpaper.
    // Force it opaque.
    color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
    implicitWidth: 560
    implicitHeight: 720
    minimumSize: Qt.size(420, 420)
    visible: false

    onVisibleChanged: if (!visible && !root.closingFromHost) root.requestClose()

    VaultContent {
      id: content
      anchors.fill: parent
      anchors.margins: Style.space(4)
      bar: root.bar
      hostWidget: root.hostWidget
      windowMode: true

      onCloseRequested: root.requestClose()
    }
  }
}
