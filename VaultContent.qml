import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The vault UI itself — list, filter, add/edit form, key handling.
// Hosted by BOTH surfaces so there is one definition of the content:
//   Panel.qml       bar popup (layershell; dismisses on focus loss)
//   VaultWindow.qml full application window (survives focus loss)
// The host owns its own lifecycle and reacts to closeRequested/tabRequested.
FocusScope {
  id: root

  property QtObject bar: null
  property var hostWidget: null
  // Window hosts have no bar popup to dismiss and no sibling panels to tab to.
  property bool windowMode: false

  signal closeRequested()
  signal tabRequested(int direction)
  // Popup hosts answer this by handing over to the full window.
  signal windowRequested()

  property alias keyCatcher: keyCatcher


  implicitHeight: column.implicitHeight

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

  // Hover selection is armed on a delay so the panel opening under the
  // cursor does not instantly reselect a row. A window is positioned by the
  // user, so there is nothing to guard against.
  function armHover() {
    if (root.windowMode) { root.hoverArmed = true; return }
    root.hoverArmed = false
    hoverArm.restart()
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

  function startEdit() {
    var s = selected()
    if (!s) return
    addName.text = s.name
    root.adding = true
    addValue.forceActiveFocus()
  }

  function submitAdd() {
    var name = addName.text.trim()
    if (name === "" || addValue.text === "" || actionProc.running) return
    var exists = root.secrets.some(s => s.name === name)
    actionProc.command = ["bash", "-c",
      'printf %s "$VAULT_VALUE" | secret-tool store --label="agent-vault: $VAULT_NAME" vault agent name "$VAULT_NAME"']
    actionProc.environment = ({ VAULT_NAME: name, VAULT_VALUE: addValue.text })
    actionProc.pendingRefresh = true
    actionProc.running = true
    root.notice = (exists ? "Updated '" : "Stored '") + name + "'"
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

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: root.closeRequested()
    onTabRequested: function(direction) { if (!root.windowMode) root.tabRequested(direction) }
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
      else if (text === "e") root.startEdit()
      else if (text === "o" && !root.windowMode) root.windowRequested()
      else if (text === "a") { addName.text = ""; root.adding = true; addName.forceActiveFocus() }
    }

    Column {
      id: column
      width: parent.width
      spacing: Style.space(6)

      // Height of every row except the list, so the list can claim the rest
      // in window mode. Nothing here depends on the list: no binding loop.
      readonly property real chromeHeight: hero.height + searchInput.height
        + sepTop.height + (emptyNote.visible ? emptyNote.height : 0)
        + sepBottom.height + (addForm.visible ? addForm.height : 0)
        + footerRow.height + spacing * 7

      // ---- Hero: title + count + add button.
      Item {
        id: hero
        width: parent.width
        height: Style.space(52)

        Rectangle {
          id: addBtn
          anchors.right: parent.right
          anchors.rightMargin: root.windowMode ? Style.space(16) : winBtn.width + Style.space(24)
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

        // Hand-off to the full window. The popup dismisses on focus loss, so
        // a value you must first copy out of another app cannot be typed here
        // — this button (or the o key) moves the session into a real window.
        Rectangle {
          id: winBtn
          visible: !root.windowMode
          anchors.right: parent.right
          anchors.rightMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          width: winBtnText.implicitWidth + Style.space(20)
          height: winBtnText.implicitHeight + Style.space(10)
          radius: height / 2
          color: winBtnArea.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"
          border.width: 1
          border.color: root.faint

          Text {
            id: winBtnText
            anchors.centerIn: parent
            text: "\u2922 Window"
            color: root.fg
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: winBtnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.windowRequested()
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

      PanelSeparator { id: sepTop; width: parent.width }

      // ---- Secret rows.
      ListView {
        id: secretList
        width: parent.width
        // Popup: grow to fit, capped. Window: take all the space the other
        // rows leave, so the content fills the window instead of stranding it.
        height: root.windowMode
          ? Math.max(Style.space(120), root.height - column.chromeHeight)
          : Math.min(contentHeight, Style.space(360))
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
                     {key: "edit", label: "e Edit", danger: false},
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
                    onClicked: {
                      var k = parent.modelData.key
                      if (k === "copy") root.copySelected()
                      else if (k === "edit") root.startEdit()
                      else root.requestDelete()
                    }
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
        id: emptyNote
        width: parent.width - Style.space(32)
        x: Style.space(16)
        visible: !root.loading && root.shown.length === 0
        text: "No secrets yet — press a to add one, or use the secret_set tool from pi."
        wrapMode: Text.WordWrap
        color: root.dimmed
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      PanelSeparator { id: sepBottom; width: parent.width }

      // ---- Add form.
      Column {
        id: addForm
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
          placeholderText: root.secrets.some(s => s.name === addName.text.trim()) ? "new value (replaces current)" : "value"
          echoMode: TextInput.Password
          font.pixelSize: Style.font.caption
          onAccepted: root.submitAdd()
          Keys.onEscapePressed: { root.adding = false; keyCatcher.forceActiveFocus() }
        }
      }

      // ---- Footer: key hints.
      Item {
        id: footerRow
        width: parent.width
        height: footerHints.implicitHeight + Style.space(14)

        Text {
          id: footerHints
          anchors.right: parent.right
          anchors.rightMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          text: root.adding ? "↵ save · esc cancel"
            : (root.windowMode
              ? "↵/y copy · a add · e edit · d delete ×2 · / filter · r refresh"
              : "↵/y copy · a add · e edit · d delete ×2 · / filter · o window · esc")
          color: root.dimmed
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
