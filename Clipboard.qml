// Clipboard Cards: Omarchy's clipboard manager with a card layout.
//
// Based on the `omarchy.clipboard` plugin from Omarchy (MIT). The layout
// follows the clipboard launcher and preview panel of Omacale
// (https://github.com/AyushKr2003/omacale, GPL-3.0), itself after Caelestia.
// Recording, history, and the paste/copy/open commands are Omarchy's own.
// SPDX-License-Identifier: GPL-3.0-only

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool clearConfirmOpen: false
  property var history: []

  property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  property string captureScript: root.omarchyPath + "/shell/plugins/clipboard/capture.sh"
  // Shares the [menu] surface tokens — themes that style the menu also
  // style the clipboard. Selected-row colors composed in the
  // singleton so consumers drop them straight into Rectangle bindings.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(40), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  // Restyled after Omacale's clipboard launcher: the history list and the
  // preview are two separate cards side by side, and the preview card is
  // only as tall as what it shows.
  property int stageWidth: Math.min(Style.space(960), panel.width - Style.gapsOut * 2)
  property int previewGap: Style.space(10)
  property int cardWidth: Math.round(stageWidth * 0.44)
  property int previewWidth: stageWidth - cardWidth - previewGap
  property int cardHeight: Math.min(Style.space(600), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(54), Style.font.title + Style.font.caption + Style.spacing.rowPaddingX * 2)
  readonly property var activeRow: displayModel.count > 0 && selectedIndex >= 0 && selectedIndex < displayModel.count ? displayModel.get(selectedIndex) : null
  readonly property bool previewShown: activeRow !== null

  function rowDetail(entryType, fullText, previewText, path, mime) {
    if (entryType === "image") return "Image · " + mime
    if (entryType === "file") return path || previewText
    var trimmed = fullText.trim()
    var words = trimmed ? trimmed.split(/\s+/).length : 0
    // displayRows caps the text it keeps; past that the counts are a floor.
    var more = fullText.length >= 8192 ? "+" : ""
    return fullText.length + more + " characters, " + words + more + " words"
  }

  function scrollPreview(delta) {
    var max = Math.max(0, previewFlick.contentHeight - previewFlick.height)
    previewFlick.contentY = Math.max(0, Math.min(max, previewFlick.contentY + delta))
  }

  onSelectedIndexChanged: previewFlick.contentY = 0
  property int historyLimit: 300

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.cancelClearHistory()
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function normalizeEntry(value) {
    return ClipboardHistory.normalizeEntry(value)
  }

  function entryKey(entry) {
    return ClipboardHistory.entryKey(entry)
  }

  function loadHistory(raw) {
    root.history = ClipboardHistory.parseHistory(raw)
    if (root.opened) root.rebuildDisplay()
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(root.history.slice(0, root.historyLimit), null, 2) + "\n")
  }

  function addClipboardEntry(entry) {
    var normalized = ClipboardHistory.normalizeEntry(entry)
    if (!normalized) return

    root.history = ClipboardHistory.addEntry(root.history, normalized, root.historyLimit)
    root.saveHistory()
    if (root.opened) root.rebuildDisplay()
  }

  function addClipboardJson(line) {
    root.addClipboardEntry(ClipboardHistory.parseEntryJson(line))
  }

  function requestClearHistory() {
    if (root.history.length === 0) return
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function cancelClearHistory() {
    root.clearConfirmOpen = false
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmClearHistory() {
    root.history = ClipboardHistory.clearHistory()
    root.saveHistory()
    root.selectedIndex = 0
    root.cursorActive = false
    root.disarmPointer()
    root.clearConfirmOpen = false
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function removeDisplayIndex(index) {
    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    root.history = ClipboardHistory.removeEntryAt(root.history, row.historyIndex)
    root.saveHistory()

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }

    root.disarmPointer()
    root.rebuildDisplay()
  }

  function rebuildDisplay() {
    var rows = ClipboardHistory.displayRows(root.history, root.filterText, 50)

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      displayModel.append({
        entryType: row.entryType,
        fullText: row.fullText,
        previewText: row.previewText,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        path: row.path,
        mime: row.mime,
        historyIndex: row.index
      })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.applySelected(row)
  }

  function copyIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.copySelected(row)
  }

  function openIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.openSelected(row)
  }

  function applySelected(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", row.mime, row.path])
    } else if (row.fullText) {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--shift-insert", "--history-index", String(row.historyIndex)])
    }
  }

  function copySelected(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", "--copy-only", row.mime, row.path])
    } else if (row.fullText) {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(row.historyIndex)])
    }
  }

  function openSelected(row) {
    if (!row) return
    root.opened = false
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-open", "--history-index", String(row.historyIndex)])
  }

  Component.onCompleted: initProc.running = true

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
    onFileChanged: reload()
  }

  // Reap watchers left behind by a previous shell instance, then start our
  // own. The pdeathsig on the watchers makes the kernel kill them whenever
  // the shell exits, however it exits, so no further lifecycle management.
  Process {
    id: initProc
    command: ["pkill", "-f", "wl-paste .*--watch .*/shell/plugins/clipboard/capture\\.sh"]
    onExited: {
      currentProc.running = true
      textWatchProc.running = true
      imageWatchProc.running = true
    }
  }

  Process {
    id: currentProc
    command: [root.captureScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addClipboardJson(text)
    }
  }

  Process {
    id: textWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Process {
    id: imageWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.captureScript, "image/png"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  // A watcher that dies takes clipboard history with it, silently: copying still
  // works, the picker still opens, and the old entries are all still there, so
  // nothing recorded until the next shell reload. Bring it back instead.
  Timer {
    id: watchRestartTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!textWatchProc.running) textWatchProc.running = true
      if (!imageWatchProc.running) imageWatchProc.running = true
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Item {
      id: stage
      width: root.previewShown ? root.stageWidth : root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.left: parent.left
      anchors.top: parent.top
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.clearConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.clearConfirmOpen) {
            if (clearConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.close()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            if (event.modifiers & Qt.ShiftModifier) root.requestClearHistory()
            else root.removeDisplayIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Up && (event.modifiers & Qt.ShiftModifier)) {
            root.scrollPreview(-Style.space(60))
            event.accepted = true
          } else if (event.key === Qt.Key_Down && (event.modifiers & Qt.ShiftModifier)) {
            root.scrollPreview(Style.space(60))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(displayModel.count - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive && (event.modifiers & Qt.AltModifier)) root.openIndex(root.selectedIndex)
            else if (root.cursorActive && (event.modifiers & Qt.ShiftModifier)) root.copyIndex(root.selectedIndex)
            else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: clearConfirm

          anchors.fill: parent
          opened: root.clearConfirmOpen
          z: 10
          message: "Delete entire clipboard history?"
          confirmText: "Delete"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelClearHistory()
          onConfirmed: root.confirmClearHistory()
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: Util.alpha(root.foreground, 0.06)

          Text {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍉"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Text {
            textFormat: Text.PlainText
            anchors.left: searchIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Search clipboard…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: Style.space(4)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: row
              required property int index
              required property string entryType
              required property string previewText
              required property string fullText
              required property string previewImage
              required property string path
              required property string mime

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
              readonly property bool hasThumb: previewImage.length > 0
              readonly property color textColor: hasCursor ? root.selectedText : root.foreground

              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              // One slot width for the icon and the thumbnail, so every
              // row's text starts at the same place.
              Item {
                id: slot
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: height
                height: parent.height - Style.space(14)

                Text {
                  visible: !row.hasThumb
                  anchors.centerIn: parent
                  text: row.entryType === "file" ? "󰈔" : "󰈙"
                  color: row.textColor
                  opacity: 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                }

                Rectangle {
                  visible: row.hasThumb
                  anchors.fill: parent
                  radius: root.cornerRadius
                  color: Util.alpha(root.foreground, 0.08)
                  clip: true

                  Image {
                    anchors.fill: parent
                    source: row.previewImage
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                  }
                }
              }

              Column {
                anchors.left: slot.right
                anchors.leftMargin: Style.space(10)
                anchors.right: deleteButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.previewText
                  color: row.textColor
                  opacity: row.hasCursor ? 1.0 : 0.72
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  elide: Text.ElideRight
                  wrapMode: Text.NoWrap
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.rowDetail(row.entryType, row.fullText, row.previewText, row.path, row.mime)
                  color: row.textColor
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideMiddle
                  wrapMode: Text.NoWrap
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index)
                }
              }

              Rectangle {
                id: deleteButton
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(28)
                height: Style.space(28)
                radius: root.cornerRadius
                visible: row.hasCursor
                color: deleteMouse.containsMouse ? Util.alpha(row.textColor, 0.16) : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: "󰆴"
                  color: row.textColor
                  opacity: deleteMouse.containsMouse ? 1.0 : 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }

                MouseArea {
                  id: deleteMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.removeDisplayIndex(row.index)
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: "󰅌"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.history.length === 0 ? "Clipboard is empty" : "No matches for “" + root.filterText + "”"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }
      }
    }

    // The preview panel: its own card beside the list, as tall as the
    // selected entry needs (whole text, or the image at its own aspect
    // ratio) up to the list card's height.
    BorderSurface {
      id: previewCard
      visible: root.previewShown
      anchors.left: card.right
      anchors.leftMargin: root.previewGap
      anchors.top: card.top
      width: root.previewWidth
      height: Math.max(root.rowHeight * 2, Math.min(root.cardHeight, previewPane.fitHeight + contentTopInset + contentBottomInset))
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: previewPane
        anchors.fill: parent
        anchors.topMargin: previewCard.contentTopInset
        anchors.rightMargin: previewCard.contentRightInset
        anchors.bottomMargin: previewCard.contentBottomInset
        anchors.leftMargin: previewCard.contentLeftInset
        clip: true

        readonly property bool isImage: root.activeRow !== null && root.activeRow.previewImage.length > 0
        readonly property bool imageReady: isImage && previewImage.status === Image.Ready && previewImage.sourceSize.width > 0
        // While the next image loads the last fit stays, so the card
        // doesn't jump.
        property real imageFit: root.rowHeight * 3
        readonly property real fitHeight: isImage ? imageFit : previewBody.implicitHeight

        function refit() {
          if (!imageReady) return
          var availableWidth = root.previewWidth - previewCard.contentLeftInset - previewCard.contentRightInset
          imageFit = Math.ceil(Math.min(availableWidth, previewImage.sourceSize.width) * previewImage.sourceSize.height / previewImage.sourceSize.width)
        }
        onImageReadyChanged: refit()

        Flickable {
          id: previewFlick
          visible: !previewPane.isImage
          anchors.fill: parent
          contentWidth: width
          contentHeight: previewBody.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Text {
            id: previewBody
            textFormat: Text.PlainText
            width: previewFlick.width - Style.space(10)
            text: root.activeRow && !previewPane.isImage ? root.activeRow.fullText : ""
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            wrapMode: Text.WrapAnywhere
          }
        }

        Rectangle {
          id: previewScroll
          visible: !previewPane.isImage && previewFlick.contentHeight > previewFlick.height + 1
          anchors.right: parent.right
          width: Style.space(3)
          radius: width / 2
          color: Util.alpha(root.foreground, 0.35)
          height: Math.max(Style.space(24), previewFlick.height * previewFlick.height / Math.max(1, previewFlick.contentHeight))
          y: (previewFlick.height - height) * previewFlick.contentY / Math.max(1, previewFlick.contentHeight - previewFlick.height)
        }

        Image {
          id: previewImage
          visible: previewPane.isImage
          anchors.fill: parent
          source: previewPane.isImage ? root.activeRow.previewImage : ""
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          mipmap: true
        }
      }
    }
    }
  }
}
