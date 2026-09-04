import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "pi.backup-monitor"
  ipcTarget: "pi.backup-monitor"
  manageIpc: false

  property string state: "unknown"
  property string timerActive: "unknown"
  property string serviceActive: "unknown"
  property string result: "unknown"
  property string persistent: "unknown"
  property string snapshot: ""
  property string started: ""
  property string phase: "Idle"
  property string completed: ""
  property string nextRun: ""
  property int failures7d: 0
  property string history: ""
  property string actionNote: ""
  property string statusError: ""
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  readonly property int refreshMs: Math.max(15, Number(root.setting("refreshIntervalSec", 60))) * 1000
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function applyStatus(s) {
    var previousState = state
    statusError = ""
    state = s.state || "unknown"
    timerActive = s.timerActive || "unknown"
    serviceActive = s.serviceActive || "unknown"
    result = s.result || "unknown"
    persistent = s.persistent || "unknown"
    snapshot = s.snapshot || ""
    started = s.started || ""
    phase = s.phase || "Idle"
    completed = s.completed || ""
    nextRun = s.nextRun || ""
    failures7d = Number(s.failures7d || 0)
    history = s.history || ""
    if (previousState === "running" && state === "healthy") actionNote = "Backup completed successfully"
    else if (previousState === "running" && state === "failed") actionNote = "Backup failed — check recent history"
  }
  function refresh() { if (!statusProc.running) statusProc.running = true }
  function startBackup() {
    if (startProc.running || serviceActive === "active" || serviceActive === "activating") return
    state = "running"
    serviceActive = "activating"
    phase = "Requesting systemd start"
    started = ""
    actionNote = "Starting backup…"
    startProc.errorText = ""
    startProc.running = true
  }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(root, direction)
    return false
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) root.refresh()

  Process {
    id: statusProc
    command: [root.pluginDir + "/status"]
    property bool parsed: false
    property string errorText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.applyStatus(JSON.parse(text)); statusProc.parsed = true }
        catch (e) { statusProc.parsed = false }
      }
    }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: statusProc.errorText = text.trim() }
    onRunningChanged: if (running) { parsed = false; errorText = "" }
    onExited: function(exitCode) {
      if (exitCode !== 0 || !parsed) {
        root.state = "failed"
        root.statusError = errorText !== "" ? errorText : "Could not read backup status"
      }
    }
  }
  Timer {
    interval: root.state === "running" ? 5000 : root.refreshMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function status(): string { return root.state + " snapshot=" + root.snapshot + " opened=" + root.opened }
  }

  Process {
    id: startProc
    command: ["pkexec", "systemctl", "start", "--no-block", "vic-backup.service"]
    property string errorText: ""
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: startProc.errorText = text.trim() }
    onExited: function(exitCode) {
      if (exitCode === 0) root.actionNote = "Backup accepted by systemd"
      else {
        root.actionNote = startProc.errorText !== "" ? startProc.errorText : "Could not start backup (exit " + exitCode + ")"
        root.state = "failed"
      }
      refreshDelay.restart()
    }
  }
  Timer {
    id: refreshDelay
    interval: 1500
    repeat: false
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.state === "running"
      ? "Restic backup is running — click for details"
      : root.state === "attention"
        ? "Restic backup needs attention — click for details"
        : "Restic: " + root.state + (root.snapshot !== "" ? " · " + root.snapshot : "") + " — click for details"
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: "󰆓"
          color: root.state === "failed" ? "#ff4d4d" : root.state === "healthy" ? "#39d353" : "#f5c542"
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
        }
        Rectangle {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          width: Style.space(5); height: width; radius: width / 2
          color: root.state === "failed" ? "#ff4d4d" : root.state === "healthy" ? "#39d353" : "#f5c542"
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "b" || t === "B") root.startBackup()
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
          id: content
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            Layout.fillWidth: true
            title: "Restic Backup"
            meta: root.state === "healthy" ? "Protected"
              : root.state === "running" ? root.phase
              : root.state === "attention" ? "Backup needs attention"
              : "Backup failed"
            detail: root.snapshot !== "" ? "Latest snapshot " + root.snapshot : "No snapshot found in service history"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰆓"
                color: root.state === "failed" ? "#ff4d4d" : root.state === "healthy" ? "#39d353" : "#f5c542"
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }
          PanelSectionHeader { Layout.fillWidth: true; text: "STATUS"; foreground: root.foreground; fontFamily: root.fontFamily }

          Text { Layout.fillWidth: true; text: "Timer: " + root.timerActive + "    Service: " + root.serviceActive + "    Result: " + (root.state === "running" ? "in progress" : root.result); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
          Text { Layout.fillWidth: true; visible: root.persistent !== "yes"; text: "Timer catch-up is not persistent"; color: "#f5c542"; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
          Text { Layout.fillWidth: true; visible: root.state === "running"; text: "Started: " + (root.started || "starting now"); color: "#f5c542"; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap }
          Text { Layout.fillWidth: true; text: "Completed: " + (root.completed || "unknown"); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap }
          Text { Layout.fillWidth: true; text: "Next: " + (root.nextRun || "unknown"); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap }
          Text { Layout.fillWidth: true; visible: root.failures7d > 0; text: root.failures7d + (root.failures7d === 1 ? " historical failure" : " historical failures") + " in the last 7 days; latest run is " + root.result; color: root.state === "failed" ? root.urgent : root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }

          RowLayout {
            id: backupAction
            Layout.fillWidth: true
            PanelActionButton { enabled: root.state !== "running"; iconText: "󰑐"; tooltipText: root.state === "running" ? "Backup already running" : "Back up now"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.startBackup() }
            Text { text: "Back up now"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
            Item { Layout.fillWidth: true }
            Text { text: "B"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            TapHandler {
              enabled: root.state !== "running"
              acceptedButtons: Qt.LeftButton
              onTapped: root.startBackup()
            }
          }
          Text { Layout.fillWidth: true; visible: root.statusError !== "" || root.actionNote !== ""; text: root.statusError !== "" ? root.statusError : root.actionNote; color: root.statusError !== "" ? root.urgent : root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }
          PanelSectionHeader { Layout.fillWidth: true; text: "RECENT HISTORY"; foreground: root.foreground; fontFamily: root.fontFamily }
          Text {
            Layout.fillWidth: true
            text: root.history !== "" ? root.history : "No recent history"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }
          Text { Layout.fillWidth: true; text: "Right-click the bar icon or press R to refresh"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
        }
      }
    }
  }
}
