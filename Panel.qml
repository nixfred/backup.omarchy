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
  // ---- metrics (see the `metrics` script) ----
  property int    mFilesNew: 0
  property int    mFilesChanged: 0
  property int    mFilesUnmodified: 0
  property real   mAddedBytes: 0
  property real   mStoredBytes: 0
  property int    mProcessedFiles: 0
  property real   mProcessedBytes: 0
  property int    mDurationSec: 0
  property real   mRepoBytes: 0
  property int    mRepoBlobs: 0
  property string mIface: ""
  property var    mHistory: []
  property var    mRuns: []
  property var    mCalendar: []
  property double mNextEpoch: 0
  property double mLastEpoch: 0
  property double nowEpoch: 0
  property var    repoSnapshots: []
  property bool   repoLoading: false
  property string repoError: ""
  property var    snapshotPaths: ({})

  // ---- anomaly detection --------------------------------------------------
  // Compare the latest run against the mean and standard deviation of the runs
  // before it. Two sigma on either duration or data added is worth a word: a
  // run that suddenly takes far longer, or ships far more, is usually the first
  // visible sign of something changing (a new large directory, a repo needing a
  // prune, a link gone slow). Deliberately advisory, never an alarm — this is a
  // small sample and normal days vary.
  readonly property var forecast: {
    var ok = []
    for (var i = 0; i < mRuns.length; i++) if (mRuns[i].ok && mRuns[i].dur > 0) ok.push(mRuns[i])
    if (ok.length < 5) return { have: false, notes: [] }

    var hist = ok.slice(0, ok.length - 1)
    var last = ok[ok.length - 1]

    function stats(pick) {
      var n = hist.length, sum = 0
      for (var i = 0; i < n; i++) sum += pick(hist[i])
      var mean = sum / n, v = 0
      for (var j = 0; j < n; j++) { var d = pick(hist[j]) - mean; v += d * d }
      return { mean: mean, sd: Math.sqrt(v / n) }
    }

    var d = stats(function(r) { return r.dur })
    var a = stats(function(r) { return r.added })
    var notes = []

    if (d.sd > 0 && Math.abs(last.dur - d.mean) > 2 * d.sd)
      notes.push((last.dur > d.mean ? "Slower" : "Faster") + " than usual: "
                 + root.humanDur(last.dur) + " vs " + root.humanDur(d.mean) + " typical")
    if (a.sd > 0 && Math.abs(last.added - a.mean) > 2 * a.sd)
      notes.push((last.added > a.mean ? "Larger" : "Smaller") + " than usual: "
                 + root.humanBytes(last.added) + " vs " + root.humanBytes(a.mean) + " typical")

    var fails = 0
    for (var k = 0; k < mRuns.length; k++) if (!mRuns[k].ok) fails++
    if (fails > 0) notes.push(fails + (fails === 1 ? " failed run" : " failed runs") + " in the log")

    return { have: true, notes: notes, meanDur: d.mean, meanAdded: a.mean, samples: hist.length }
  }

  function humanBytes(b) {
    b = Number(b) || 0
    if (b < 1024) return Math.round(b) + " B"
    if (b < 1048576) return (b / 1024).toFixed(0) + " KiB"
    if (b < 1073741824) return (b / 1048576).toFixed(1) + " MiB"
    if (b < 1099511627776) return (b / 1073741824).toFixed(2) + " GiB"
    return (b / 1099511627776).toFixed(2) + " TiB"
  }
  function humanDur(sec) {
    sec = Math.round(Number(sec) || 0)
    if (sec < 60) return sec + "s"
    var m = Math.floor(sec / 60), r = sec % 60
    if (m < 60) return m + "m " + r + "s"
    return Math.floor(m / 60) + "h " + (m % 60) + "m"
  }
  // Average bytes/sec across the last run — the honest end-to-end figure,
  // including scan time, not just the transfer bursts the live graph shows.
  readonly property real mAvgRate: mDurationSec > 0 ? mProcessedBytes / mDurationSec : 0
  readonly property real mDedupSaved: Math.max(0, mAddedBytes - mStoredBytes)

  function applyMetrics(m) {
    mFilesNew = Number(m.filesNew || 0)
    mFilesChanged = Number(m.filesChanged || 0)
    mFilesUnmodified = Number(m.filesUnmodified || 0)
    mAddedBytes = Number(m.addedBytes || 0)
    mStoredBytes = Number(m.storedBytes || 0)
    mProcessedFiles = Number(m.processedFiles || 0)
    mProcessedBytes = Number(m.processedBytes || 0)
    mDurationSec = Number(m.durationSec || 0)
    mRepoBytes = Number(m.repoBytes || 0)
    mRepoBlobs = Number(m.repoBlobs || 0)
    mIface = m.iface || ""
    mRuns = m.runs || []
    mCalendar = m.calendar || []
    mNextEpoch = Number(m.nextEpoch || 0)
    mLastEpoch = Number(m.lastEpoch || 0)
    nowEpoch = Number(m.now || 0)
    // The history chart reads the same run records.
    mHistory = mRuns
  }

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
  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!metricsProc.running) metricsProc.running = true
  }
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

  // One-shot metrics: last-run stats and run history parsed out of the restic
  // log. Cheap enough to re-run on every refresh.
  Process {
    id: metricsProc
    command: [root.pluginDir + "/metrics"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.applyMetrics(JSON.parse(text)) } catch (e) { /* keep last good values */ }
      }
    }
  }

  // Live throughput. One long-lived reader emitting a sample per second, rather
  // than re-spawning a process 60 times a minute. Only runs while the panel is
  // actually on screen — there is nothing to draw otherwise.
  Process {
    id: netStream
    command: [root.pluginDir + "/metrics", "--stream"]
    running: root.opened
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var d = JSON.parse(line)
          if (d && d.tx !== undefined) throughput.addSample(d.rx, d.tx)
        } catch (e) { /* a partial line during teardown is not worth reporting */ }
      }
    }
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
  // Drives the countdown ring. A plain 1 Hz tick — the ring repaints on a data
  // change, which is what a new second is, rather than animating per frame.
  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.nowEpoch = root.nowEpoch + 1
  }

  // Repository queries. Both hit B2 through pkexec and are user-initiated only.
  Process {
    id: snapshotsProc
    command: [root.pluginDir + "/metrics", "--snapshots"]
    onRunningChanged: if (running) { root.repoLoading = true; root.repoError = "" }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var arr = JSON.parse(text)
          root.repoSnapshots = Array.isArray(arr) ? arr : []
          if (root.repoSnapshots.length === 0) root.repoError = "Repository returned no snapshots"
        } catch (e) { root.repoError = "Could not read snapshot list" }
      }
    }
    onExited: function(code) {
      root.repoLoading = false
      if (code !== 0 && root.repoSnapshots.length === 0)
        root.repoError = code === 126 ? "Authentication declined" : "Repository query failed"
    }
  }

  Process {
    id: lsProc
    property string forId: ""
    command: [root.pluginDir + "/metrics", "--ls", lsProc.forId]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // `restic ls --json` streams one object per line: a snapshot header
        // then a node per entry. Only top-level paths are interesting here.
        var top = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].trim() === "") continue
          try {
            var o = JSON.parse(lines[i])
            if (o.path && o.path.split("/").length === 2) top.push(o.path)
          } catch (e) { /* header lines and partials are expected */ }
        }
        var m = ({})
        for (var k in root.snapshotPaths) m[k] = root.snapshotPaths[k]
        m[lsProc.forId] = top
        root.snapshotPaths = m
      }
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

        // Last seven runs as a micro chart, so the trend is readable from the
        // bar without opening anything.
        Sparkline {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 1
          width: Style.space(14)
          height: Style.space(9)
          runs: root.mRuns
          accent: root.state === "failed" ? "#ff4d4d" : "#39d353"
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
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(820))

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
          PanelSectionHeader {
            Layout.fillWidth: true
            text: root.state === "running" ? "LIVE THROUGHPUT — UPLOADING TO B2" : "NETWORK THROUGHPUT · " + (root.mIface || "link")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ThroughputGraph {
            id: throughput
            Layout.fillWidth: true
            active: root.state === "running"
            accent: root.state === "running" ? "#39d353" : Color.accent
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            Layout.fillWidth: true
            visible: root.state !== "running"
            text: "Idle — this is total link traffic, not backup traffic. During a run it is dominated by the upload."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }
          PanelSectionHeader { Layout.fillWidth: true; text: "LAST SNAPSHOT"; foreground: root.foreground; fontFamily: root.fontFamily }

          // Headline figures for the most recent run.
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(16)
            Column {
              spacing: 1
              Text { text: root.humanBytes(root.mProcessedBytes); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
              Text { text: "scanned"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            }
            Column {
              spacing: 1
              Text { text: root.humanDur(root.mDurationSec); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
              Text { text: "duration"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            }
            Column {
              spacing: 1
              Text { text: throughput.humanRate(root.mAvgRate); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
              Text { text: "avg rate"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            }

            Item { Layout.fillWidth: true }
          }

          // The countdown gets its own row. It was tried beside the throughput
          // graph (pushed past the panel edge) and inside the stats row (squeezed
          // "67.86 GiB" down to "iiB"): at this panel width nothing else can
          // share a line with it.
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(10)

            Text {
              text: root.state === "running" ? "Backup in progress" : "Next scheduled run"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Item { Layout.fillWidth: true }
            NextRunRing {
              Layout.preferredWidth: Style.space(58)
              Layout.preferredHeight: Style.space(58)
              nextEpoch: root.mNextEpoch
              lastEpoch: root.mLastEpoch
              nowEpoch: root.nowEpoch
              running: root.state === "running"
              accent: Color.accent
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
          }

          // How much of the change survived compression + dedup.
          RatioBar {
            Layout.fillWidth: true
            label: "DEDUP & COMPRESSION"
            trailing: root.mAddedBytes > 0
              ? root.humanBytes(root.mStoredBytes) + " stored of " + root.humanBytes(root.mAddedBytes)
              : "no data"
            foreground: root.foreground
            fontFamily: root.fontFamily
            segments: [
              { value: root.mStoredBytes, color: Color.accent, name: "stored" },
              { value: root.mDedupSaved, color: Qt.rgba(0.22, 0.83, 0.33, 0.55), name: "saved " + (root.mAddedBytes > 0 ? Math.round(root.mDedupSaved / root.mAddedBytes * 100) + "%" : "") }
            ]
          }

          // What actually changed in the tree — the closest thing available to
          // "what is being updated" without per-file logging.
          RatioBar {
            Layout.fillWidth: true
            label: "FILE CHURN"
            trailing: root.mProcessedFiles > 0 ? root.mProcessedFiles.toLocaleString(Qt.locale(), "f", 0) + " files" : "no data"
            foreground: root.foreground
            fontFamily: root.fontFamily
            segments: [
              { value: root.mFilesNew, color: "#39d353", name: root.mFilesNew + " new" },
              { value: root.mFilesChanged, color: "#f5c542", name: root.mFilesChanged + " changed" },
              { value: root.mFilesUnmodified, color: Qt.rgba(1, 1, 1, 0.14), name: root.mFilesUnmodified + " unchanged" }
            ]
          }

          Text {
            Layout.fillWidth: true
            visible: root.mRepoBytes > 0
            text: "Repository " + root.humanBytes(root.mRepoBytes) + " across " + root.mRepoBlobs.toLocaleString(Qt.locale(), "f", 0) + " blobs"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // Advisory anomaly notes. Absent entirely when the latest run looks
          // like every other run, which is the common case.
          Repeater {
            model: root.forecast.have ? root.forecast.notes : []
            Text {
              required property var modelData
              Layout.fillWidth: true
              text: "▲  " + modelData
              color: "#f5c542"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }
          Text {
            Layout.fillWidth: true
            visible: root.forecast.have && root.forecast.notes.length === 0
            text: "✓  In line with the previous " + root.forecast.samples + " runs ("
                  + root.humanDur(root.forecast.meanDur) + " / "
                  + root.humanBytes(root.forecast.meanAdded) + " typical)"
            color: "#39d353"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }
          PanelSectionHeader { Layout.fillWidth: true; text: "BACKUP CALENDAR"; foreground: root.foreground; fontFamily: root.fontFamily }

          Heatmap {
            Layout.fillWidth: true
            calendar: root.mCalendar
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }
          PanelSectionHeader { Layout.fillWidth: true; text: "SNAPSHOTS"; foreground: root.foreground; fontFamily: root.fontFamily }

          SnapshotList {
            Layout.fillWidth: true
            runs: root.mRuns
            repoSnapshots: root.repoSnapshots
            loading: root.repoLoading
            errorText: root.repoError
            pathsById: root.snapshotPaths
            foreground: root.foreground
            fontFamily: root.fontFamily
            onLoadRepoRequested: if (!snapshotsProc.running) snapshotsProc.running = true
            onListPathsRequested: function(id) {
              if (lsProc.running) return
              lsProc.forId = id
              lsProc.running = true
            }
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }
          PanelSectionHeader { Layout.fillWidth: true; text: "RUN HISTORY — DATA ADDED PER RUN"; foreground: root.foreground; fontFamily: root.fontFamily }

          HistoryBars {
            Layout.fillWidth: true
            runs: root.mHistory
            accent: Color.accent
            foreground: root.foreground
            fontFamily: root.fontFamily
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
