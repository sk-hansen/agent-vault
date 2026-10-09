import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "skh.agent-vault"

  property int secretCount: -1

  function refreshCount() {
    if (!countProc.running) countProc.running = true
  }

  Timer {
    interval: 600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshCount()
  }

  Process {
    id: countProc
    command: ["python3", Qt.resolvedUrl("list-secrets").toString().replace(/^file:\/\//, "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.secretCount = JSON.parse(text).secrets.length } catch (e) { root.secretCount = -1 }
      }
    }
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Full application window (the plugin's `panel` entry point). A plugin may
  // not host its own window from a bar-widget Loader \u2014 the shell's panel
  // loader owns it, so summon it the documented way. The plugin declares both
  // `bar-widget` and `panel`, which routes summon to the panel loader.
  function openWindow() {
    if (!summonProc.running) summonProc.running = true
  }

  Process {
    id: summonProc
    command: ["omarchy-shell", "shell", "summon", "skh.agent-vault", "{}"]
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onStatusChanged: if (status === Loader.Error) console.warn("skh.agent-vault Panel.qml failed to load")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    readonly property string lockGlyph: String.fromCodePoint(0xF033E)  // nf-md-lock
    text: root.secretCount > 0 ? lockGlyph + " " + root.secretCount : lockGlyph
    fontSize: Style.font.caption
    tooltipText: (root.secretCount >= 0
      ? "Agent Vault — " + root.secretCount + " secret" + (root.secretCount === 1 ? "" : "s")
      : "Agent Vault") + "\nright-click: open as window"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refreshCount()
      else if (buttonCode === Qt.RightButton) root.openWindow()
      else root.togglePanel()
    }
  }
}
