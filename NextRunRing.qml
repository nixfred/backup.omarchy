import QtQuick
import qs.Commons

// Countdown to the next scheduled run, drawn as a filling arc.
//
// The arc represents the whole gap between the last trigger and the next one,
// so the sweep is "how much of this cycle has elapsed" rather than an abstract
// timer. At a glance you can tell whether the next backup is hours away or
// imminent without reading the clock.
//
// Repaints once a second — a data change, not an animation. The only
// continuously animated element is the imminent-run glow, which is scene-graph
// opacity.
Item {
  id: root

  property double nextEpoch: 0
  property double lastEpoch: 0
  property double nowEpoch: 0       // driven by the panel's clock
  property bool running: false      // a backup is happening right now
  property color accent: Color.accent
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  readonly property double cycle: Math.max(1, nextEpoch - lastEpoch)
  readonly property double remaining: Math.max(0, nextEpoch - nowEpoch)
  readonly property real progress:
    nextEpoch <= 0 ? 0 : Math.max(0, Math.min(1, 1 - remaining / cycle))
  // Under fifteen minutes reads as "about to happen".
  readonly property bool imminent: !running && nextEpoch > 0 && remaining > 0 && remaining < 900

  function humanRemaining() {
    if (running) return "now"
    if (nextEpoch <= 0) return "—"
    var s = Math.round(remaining)
    if (s <= 0) return "due"
    // Kept deliberately short: this label lives inside a 62px ring that sits
    // flush against the panel edge, so "58m 40s" overflowed and got clipped.
    // One unit of precision is plenty for a countdown to a nightly job.
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60)
    if (h >= 24) return Math.floor(h / 24) + "d " + (h % 24) + "h"
    if (h > 0) return h + "h " + m + "m"
    if (m > 0) return m + "m"
    return s + "s"
  }

  implicitWidth: Style.space(62)
  implicitHeight: Style.space(62)

  onProgressChanged: arc.requestPaint()
  onRunningChanged: arc.requestPaint()
  onAccentChanged: arc.requestPaint()
  onForegroundChanged: arc.requestPaint()

  // Imminent / running glow. Scene-graph only.
  //
  // Every reference here is by id, never `parent`. An Animation is not an Item,
  // so `parent` inside one does not resolve on the animation: it climbs the
  // scope chain to this component's root and yields root.parent — the row that
  // hosts the ring. That made the pulse fade and scale the entire "Next
  // scheduled run" row, and `running` never turned off because the row is
  // always visible.
  Rectangle {
    id: glow
    anchors.centerIn: parent
    width: Math.min(root.width, root.height)
    height: width
    radius: width / 2
    color: "transparent"
    border.width: 2
    border.color: root.running ? "#39d353" : root.accent
    visible: root.running || root.imminent
    opacity: 0
    scale: 1.0

    SequentialAnimation {
      running: glow.visible
      loops: Animation.Infinite
      ParallelAnimation {
        NumberAnimation { target: glow; property: "opacity"; from: 0.55; to: 0; duration: 1400; easing.type: Easing.OutQuad }
        NumberAnimation { target: glow; property: "scale"; from: 1.0; to: 1.35; duration: 1400; easing.type: Easing.OutQuad }
      }
    }
  }

  Canvas {
    id: arc
    anchors.fill: parent
    renderTarget: Canvas.Image
    renderStrategy: Canvas.Cooperative

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width, h = height
      if (w <= 0 || h <= 0) return
      var cx = w / 2, cy = h / 2
      var r = Math.min(w, h) / 2 - 4
      if (r <= 1) return

      // Track
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.lineWidth = 3
      ctx.strokeStyle = Util.alpha(root.foreground, 0.12).toString()
      ctx.stroke()

      // Elapsed sweep, from 12 o'clock
      var col = root.running ? "#39d353" : root.accent
      if (root.progress > 0.001) {
        ctx.save()
        ctx.shadowColor = Util.alpha(col, 0.45).toString()
        ctx.shadowBlur = 5
        ctx.beginPath()
        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * root.progress)
        ctx.lineWidth = 3.4
        ctx.lineCap = "round"
        ctx.strokeStyle = col.toString()
        ctx.stroke()
        ctx.restore()
      }
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 0

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: root.width - Style.space(12)
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: root.humanRemaining()
      color: root.running ? "#39d353" : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: root.width - Style.space(12)
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: root.running ? "running" : "next"
      color: Util.alpha(root.foreground, 0.50)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
