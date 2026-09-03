import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "skh.agent-vault"
  ipcTarget: "skh.agent-vault"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var secrets: []
  property int selectedIndex: 0
  property bool loading: false
  property bool confirmingDelete: false
  property int copiedIndex: -1
  property bool adding: false
  property string notice: ""
  property bool hoverArmed: false
  property real lastMouseX: -1
  property real lastMouseY: -1

  onSelectedIndexChanged: root.confirmingDelete = false

  readonly property string helper: Qt.resolvedUrl("list-secrets").toString().replace(/^file:\/\//, "")
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color dimmed: Qt.darker(fg, 1.4)
  readonly property color faint: Qt.darker(fg, 1.9)

  readonly property var shown: {
    var q = searchInput.text.trim().toLowerCase()
    if (q === "") return root.secrets
    return root.secrets.filter(s => s.name.toLowerCase().indexOf(q) >= 0)
  }

  function open() {
    root.controller.show()
    root.hoverArmed = false
    hoverArm.restart()
    refresh()
  }
  function openFromHotkey() { open() }
  function close() {
    root.adding = false
    root.controller.hide()
  }
  function toggle() { root.opened ? close() : open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    root.selectedIndex = 0
    root.notice = ""
    if (!listProc.running) {
      root.loading = true
      listProc.running = true
    }
    if (root.hostWidget && root.hostWidget.refreshCount) root.hostWidget.refreshCount()
  }

  function selected() {
    return root.shown.length > 0 ? root.shown[root.selectedIndex] : null
  }

  function copySelected() {
    var s = selected()
    if (!s || actionProc.running) return
    actionProc.command = ["bash", "-c",
      'secret-tool lookup vault agent name "$0" | wl-copy', s.name]
    actionProc.pendingRefresh = false
    actionProc.running = true
    root.copiedIndex = root.selectedIndex
    copiedReset.restart()
  }

  function requestDelete() {
    var s = selected()
    if (!s || actionProc.running) return
    if (!root.confirmingDelete) {
      root.confirmingDelete = true
      return
    }
    root.confirmingDelete = false
    actionProc.command = ["secret-tool", "clear", "vault", "agent", "name", s.name]
    actionProc.pendingRefresh = true
    actionProc.running = true
  }

  function submitAdd() {
    var name = addName.text.trim()
    if (name === "" || addValue.text === "" || actionProc.running) return
    actionProc.command = ["bash", "-c",
      'printf %s "$VAULT_VALUE" | secret-tool store --label="agent-vault: $VAULT_NAME" vault agent name "$VAULT_NAME"']
    actionProc.environment = ({ VAULT_NAME: name, VAULT_VALUE: addValue.text })
    actionProc.pendingRefresh = true
    actionProc.running = true
    root.notice = "Stored '" + name + "'"
    addName.text = ""
    addValue.text = ""
    root.adding = false
    keyCatcher.forceActiveFocus()
  }

  Timer {
    id: hoverArm
    interval: 800
    onTriggered: root.hoverArmed = true
  }

  Timer {
    id: copiedReset
    interval: 1500
    onTriggered: root.copiedIndex = -1
  }

  Timer {
    id: actionDeadline
    interval: 8000
    onTriggered: if (actionProc.running) actionProc.running = false
  }

  Process {
    id: actionProc
    property bool pendingRefresh: false
    onRunningChanged: running ? actionDeadline.restart() : actionDeadline.stop()
    onExited: {
      actionProc.environment = ({})
      if (pendingRefresh) { pendingRefresh = false; root.refresh() }
    }
  }

  Process {
    id: listProc
    command: ["python3", root.helper]
    onExited: root.loading = false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.loading = false
        try {
          var parsed = JSON.parse(text)
          root.secrets = parsed.secrets || []
          if (parsed.error) root.notice = String(parsed.error)
        } catch (e) {
          root.secrets = []
          root.notice = "Could not read the keyring"
        }
        if (root.selectedIndex >= root.shown.length)
          root.selectedIndex = Math.max(0, root.shown.length - 1)
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0 && root.shown.length > 0)
          root.selectedIndex = Math.max(0, Math.min(root.shown.length - 1, root.selectedIndex + dy))
      }
      onReturnRequested: root.copySelected()
      onActivateRequested: root.copySelected()
      onTextKey: function(text) {
        if (text === "/") { searchInput.forceActiveFocus(); searchInput.selectAll() }
        else if (text === "r") root.refresh()
        else if (text === "y") root.copySelected()
        else if (text === "d") root.requestDelete()
        else if (text === "a") { root.adding = true; addName.forceActiveFocus() }
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(6)

        // ---- Hero: title + count + add button.
        Item {
          width: parent.width
          height: Style.space(52)

          Rectangle {
            id: addBtn
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            width: addBtnText.implicitWidth + Style.space(20)
            height: addBtnText.implicitHeight + Style.space(10)
            radius: height / 2
            color: root.adding ? Color.accent
              : (addBtnArea.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent")
            border.width: root.adding ? 0 : 1
            border.color: root.faint

            Text {
              id: addBtnText
              anchors.centerIn: parent
              text: root.adding ? "✕ Cancel" : "+ Add"
              color: root.adding ? Color.background : root.fg
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: addBtnArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.adding = !root.adding
                if (root.adding) addName.forceActiveFocus()
                else keyCatcher.forceActiveFocus()
              }
            }
          }

          Column {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.right: addBtn.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "Agent Vault"
              color: root.fg
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              text: root.loading ? "Reading keyring…"
                : (root.notice !== "" ? root.notice
                  : (root.secrets.length === 0 ? "Vault is empty"
                    : root.secrets.length + " secret" + (root.secrets.length === 1 ? "" : "s")
                      + " · gnome-keyring · vault=agent"))
              elide: Text.ElideRight
              color: root.dimmed
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---- Search.
        TextField {
          id: searchInput
          width: parent.width - Style.space(32)
          x: Style.space(16)
          placeholderText: "/ filter by name"
          font.pixelSize: Style.font.caption
          onTextChanged: root.selectedIndex = 0
          onAccepted: keyCatcher.forceActiveFocus()
          Keys.onEscapePressed: {
            if (text !== "") text = ""
            else keyCatcher.forceActiveFocus()
          }
        }

        PanelSeparator { width: parent.width }

        // ---- Secret rows.
        ListView {
          id: secretList
          width: parent.width
          height: Math.min(contentHeight, Style.space(360))
          clip: true
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          model: root.shown

          delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool current: index === root.selectedIndex

            width: secretList.width
            height: rowContent.implicitHeight + Style.space(14)
            radius: Style.cornerRadius
            color: (current || rowArea.containsMouse)
              ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"

            Column {
              id: rowContent
              z: 1
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.right: rowMeta.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: row.modelData.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.fg
                font.family: "monospace"
                font.pixelSize: Style.font.body
                font.bold: row.current
              }

              Row {
                visible: row.current
                spacing: Style.space(6)
                topPadding: Style.space(4)

                Repeater {
                  model: row.current
                    ? [{key: "copy",
                        label: root.copiedIndex === row.index ? "✓ Copied" : "↵ Copy",
                        danger: false},
                       {key: "delete",
                        label: root.confirmingDelete ? "d Sure?" : "d Delete",
                        danger: true}]
                    : []

                  Rectangle {
                    required property var modelData
                    width: ctlText.implicitWidth + Style.space(16)
                    height: ctlText.implicitHeight + Style.space(8)
                    radius: height / 2
                    color: ctlArea.containsMouse
                      ? (modelData.danger && root.confirmingDelete ? Color.urgent : Color.accent)
                      : "transparent"
                    border.width: 1
                    border.color: modelData.danger && root.confirmingDelete ? Color.urgent : root.faint

                    Text {
                      id: ctlText
                      anchors.centerIn: parent
                      text: parent.modelData.label
                      textFormat: Text.PlainText
                      color: ctlArea.containsMouse ? Color.background
                        : (parent.modelData.danger && root.confirmingDelete ? Color.urgent : root.dimmed)
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      id: ctlArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: parent.modelData.key === "copy" ? root.copySelected() : root.requestDelete()
                    }
                  }
                }
              }
            }

            Text {
              id: rowMeta
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              text: String(row.modelData.modified || "").split(" ")[0]
              color: root.dimmed
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: rowArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: function(mouse) {
                if (!root.hoverArmed) return
                var g = rowArea.mapToGlobal(mouse.x, mouse.y)
                if (g.x !== root.lastMouseX || g.y !== root.lastMouseY) {
                  root.lastMouseX = g.x
                  root.lastMouseY = g.y
                  root.selectedIndex = row.index
                }
              }
              onClicked: {
                root.selectedIndex = row.index
                root.copySelected()
              }
            }
          }
        }

        // ---- Empty state.
        Text {
          width: parent.width - Style.space(32)
          x: Style.space(16)
          visible: !root.loading && root.shown.length === 0
          text: "No secrets yet — press a to add one, or use the secret_set tool from pi."
          wrapMode: Text.WordWrap
          color: root.dimmed
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator { width: parent.width }

        // ---- Add form.
        Column {
          width: parent.width - Style.space(32)
          x: Style.space(16)
          spacing: Style.space(6)
          visible: root.adding

          TextField {
            id: addName
            width: parent.width
            placeholderText: "name (e.g. keepit-api-token)"
            font.pixelSize: Style.font.caption
            font.family: "monospace"
            onAccepted: addValue.forceActiveFocus()
            Keys.onEscapePressed: { root.adding = false; keyCatcher.forceActiveFocus() }
          }

          TextField {
            id: addValue
            width: parent.width
            placeholderText: "value"
            echoMode: TextInput.Password
            font.pixelSize: Style.font.caption
            onAccepted: root.submitAdd()
            Keys.onEscapePressed: { root.adding = false; keyCatcher.forceActiveFocus() }
          }
        }

        // ---- Footer: key hints.
        Item {
          width: parent.width
          height: footerHints.implicitHeight + Style.space(14)

          Text {
            id: footerHints
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            text: root.adding ? "↵ save · esc cancel"
              : "↵/y copy · a add · d delete ×2 · / filter · r refresh · esc"
            color: root.dimmed
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
