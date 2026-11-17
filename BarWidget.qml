import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "ajukas.whatsapp"

  readonly property string url: String(setting("url", "https://web.whatsapp.com/"))
  // Web app windows are classed "<browser>-web.whatsapp.com__-Default".
  readonly property var appIdPattern: /-web\.whatsapp\.com__/
  readonly property string notificationsDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications"

  readonly property var toplevel: {
    var list = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && appIdPattern.test(list[i].appId || "")) return list[i]
    }
    return null
  }

  readonly property bool focused: toplevel !== null && ToplevelManager.activeToplevel === toplevel

  // WhatsApp Web puts the unread count in the title, e.g. "(3) WhatsApp".
  readonly property int titleUnread: {
    var match = toplevel ? /^\((\d+)\)/.exec(toplevel.title || "") : null
    return match ? parseInt(match[1]) : 0
  }

  // WhatsApp notifications seen since the window was last focused. The same
  // notification is written once as a popup and again into history, so they
  // are deduplicated by id and timestamp.
  property var seen: ({})
  property int notified: 0
  readonly property int unread: Math.max(notified, titleUnread)

  // whatsapp-popup.sh keeps the window in special:whatsapp, so hiding it leaves
  // WhatsApp running in the background.
  readonly property string popupScript: String(Qt.resolvedUrl("whatsapp-popup.sh")).replace(/^file:\/\//, "")

  onFocusedChanged: {
    if (focused) clearBadge()
    else Util.execArgv(["bash", popupScript, "hide"])
  }

  // Monitor currently showing special:whatsapp, tracked from Hyprland events.
  property string popupMonitor: ""
  readonly property var hostScreen: button.QsWindow.window ? button.QsWindow.window.screen : null
  readonly property bool popupOnThisScreen: popupMonitor !== "" && hostScreen !== null && hostScreen.name === popupMonitor

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      // A window opened while the popup had focus lands in special:whatsapp;
      // the script moves anything that is not the popup itself back out.
      if (event && event.name === "openwindow") {
        if (String(event.data || "").split(",")[1] === "special:whatsapp")
          Util.execArgv(["bash", popupScript, "evict"])
        return
      }
      if (!event || event.name !== "activespecial") return
      var parts = String(event.data || "").split(",")
      var monitor = parts.pop()
      var workspace = parts.join(",")
      if (workspace === "special:whatsapp") root.popupMonitor = monitor
      else if (monitor === root.popupMonitor) root.popupMonitor = ""
    }
  }

  // Events are only seen while the shell runs; pick up a popup that was already
  // open when the shell (re)started.
  Process {
    running: true
    command: ["bash", "-c", "hyprctl monitors -j | jq -r 'first(.[] | select(.specialWorkspace.name == \"special:whatsapp\") | .name) // empty'"]
    stdout: SplitParser {
      onRead: function(line) { if (line.trim() !== "") root.popupMonitor = line.trim() }
    }
  }

  // Clicking another window already hides the popup through the focus change;
  // this layer sits under all windows so a click on the empty desktop does too.
  PanelWindow {
    screen: root.hostScreen
    visible: root.popupOnThisScreen
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "ajukas-whatsapp-dismiss"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onPressed: Util.execArgv(["bash", root.popupScript, "dismiss"])
    }
  }

  function clearBadge() {
    seen = ({})
    notified = 0
  }

  function recordNotification(line) {
    var key = String(line || "").trim()
    if (key === "" || seen[key] || focused) return
    seen[key] = true
    notified += 1
  }

  function togglePopup() {
    clearBadge()
    Util.execArgv(["bash", popupScript, "toggle", url])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The bar forwards unhandled double-clicks to its background, which toggles
  // bar transparency. Opening and quickly closing the popup is a double-click,
  // so take it here and treat its second click as a normal one.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onDoubleClicked: function(mouse) {
      mouse.accepted = true
      root.togglePopup()
    }
  }

  Process {
    id: watcher
    running: true
    command: ["bash", "-c",
      "mkdir -p \"$1\"\n" +
      "inotifywait -m -r -q -e close_write,moved_to --format '%w%f' \"$1\" | while IFS= read -r f; do\n" +
      "  case $f in */images/*) continue ;; *.json) ;; *) continue ;; esac\n" +
      "  grep -qi whatsapp \"$f\" 2>/dev/null || continue\n" +
      "  jq -r '\"\\(.originalId)-\\(.timestamp)\"' \"$f\" 2>/dev/null\n" +
      "done", "--", root.notificationsDir]
    stdout: SplitParser {
      onRead: function(line) { root.recordNotification(line) }
    }
    onExited: restart.restart()
  }

  Timer {
    id: restart
    interval: 1000
    onTriggered: watcher.running = true
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰖣"
    active: root.unread > 0
    dimmed: root.toplevel === null && root.unread === 0
    tooltipText: root.unread > 0
      ? "WhatsApp · " + root.unread + (root.unread === 1 ? " mensagem nova" : " mensagens novas")
      : (root.toplevel ? "WhatsApp" : "Abrir WhatsApp")
    iconComponent: Component {
      Item {
        OpticalGlyph {
          id: glyph
          anchors.fill: parent
          text: button.text
          color: button.foreground
          fontFamily: button.fontFamily
          fontSize: button.fontSize
        }

        Rectangle {
          visible: root.unread > 0
          anchors.right: glyph.right
          anchors.top: glyph.top
          anchors.rightMargin: -Style.space(4)
          anchors.topMargin: -Style.space(3)
          height: Math.max(10, Math.round(button.fontSize * 0.75))
          width: Math.max(height, badgeText.implicitWidth + Style.space(4))
          radius: height / 2
          color: Color.urgent

          Text {
            id: badgeText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.unread > 99 ? "99+" : String(root.unread)
            color: Color.background
            font.family: button.fontFamily
            font.pixelSize: Math.max(7, Math.round(button.fontSize * 0.5))
            font.bold: true
          }
        }
      }
    }
    onPressed: function(b) {
      if (b === Qt.RightButton && root.toplevel) root.toplevel.close()
      else if (b === Qt.MiddleButton) root.clearBadge()
      else if (b === Qt.LeftButton) root.togglePopup()
    }
  }
}
