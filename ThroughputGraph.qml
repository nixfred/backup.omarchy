import QtQuick
import qs.Commons

// Live network throughput, the panel's centrepiece while a backup is uploading
// to B2.
//
// Repaints once per sample (1 Hz), which is a DATA change, not an animation —
// the distinction that matters, because driving a Canvas from a per-frame value
// re-rasterises it ~60x/sec and both flickers and burns CPU. The only
// continuously moving thing here is the live pip, and that is scene-graph
// opacity.
//
// Upload is the story (restic pushing to B2), so TX owns the filled area and
// the scale. RX is drawn as a thin underlay for context — during a backup it is
// mostly B2's acknowledgements, and a big RX spike with no TX usually means
// something else on the machine is downloading.
Item {
  id: root

  property int capacity: 90            // samples retained ≈ seconds of history
  property color accent: Color.accent
  property color foreground: Color.popups.text
  property bool active: false          // backup running — drives the live pip
  property string fontFamily: Style.font.family

  property var txSamples: []
  property var rxSamples: []
  readonly property real txNow: txSamples.length ? txSamples[txSamples.length - 1] : 0
  readonly property real rxNow: rxSamples.length ? rxSamples[rxSamples.length - 1] : 0

  property real windowPeak: 0

  function addSample(rx, tx) {
    var t = txSamples.slice()
    var r = rxSamples.slice()
    t.push(Math.max(0, tx))
    r.push(Math.max(0, rx))
    while (t.length > capacity) t.shift()
    while (r.length > capacity) r.shift()
    txSamples = t
    rxSamples = r

    var p = 0
    for (var i = 0; i < t.length; i++) if (t[i] > p) p = t[i]
    for (var j = 0; j < r.length; j++) if (r[j] > p) p = r[j]
    windowPeak = p

    graph.requestPaint()
  }

  function reset() {
    txSamples = []
    rxSamples = []
    windowPeak = 0
    graph.requestPaint()
  }

  // Binary units, matching what restic itself prints, so numbers here can be
  // compared with the log without a mental conversion.
  function humanRate(bytesPerSec) {
    var b = bytesPerSec || 0
    if (b < 1024) return Math.round(b) + " B/s"
    if (b < 1048576) return (b / 1024).toFixed(b < 10240 ? 1 : 0) + " KiB/s"
    if (b < 1073741824) return (b / 1048576).toFixed(b < 10485760 ? 1 : 0) + " MiB/s"
    return (b / 1073741824).toFixed(2) + " GiB/s"
  }

  implicitHeight: Style.space(120)

  Canvas {
    id: graph
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

      var padTop = 4
      var padBottom = 14           // room for the axis label strip
      var plotH = h - padTop - padBottom
      if (plotH <= 4) return

      var accentStr = root.accent.toString()

      // --- grid -------------------------------------------------------
      // Three horizontal rules. Deliberately faint: this is a shape-reading
      // chart, not a chart anyone reads exact values off.
      ctx.strokeStyle = Util.alpha(root.foreground, 0.10).toString()
      ctx.lineWidth = 1
      for (var g = 0; g <= 3; g++) {
        var gy = padTop + (plotH / 3) * g + 0.5
        ctx.beginPath()
        ctx.moveTo(0, gy)
        ctx.lineTo(w, gy)
        ctx.stroke()
      }

      var n = root.txSamples.length
      if (n < 2) {
        ctx.fillStyle = Util.alpha(root.foreground, 0.45).toString()
        ctx.font = "11px '" + root.fontFamily + "'"
        ctx.fillText("waiting for samples…", 6, padTop + plotH / 2)
        return
      }

      // Scale headroom so a flat-out link does not touch the ceiling, and a
      // floor so idle noise does not get amplified into fake mountains.
      var peak = Math.max(root.windowPeak * 1.15, 64 * 1024)
      var stepX = w / (root.capacity - 1)
      // Right-align: newest sample at the right edge, history scrolling left.
      var x0 = w - (n - 1) * stepX

      function yFor(v) { return padTop + plotH - (v / peak) * plotH }

      // --- RX underlay -------------------------------------------------
      ctx.beginPath()
      for (var r = 0; r < n; r++) {
        var rx = x0 + r * stepX, ry = yFor(root.rxSamples[r])
        r === 0 ? ctx.moveTo(rx, ry) : ctx.lineTo(rx, ry)
      }
      ctx.strokeStyle = Util.alpha(root.foreground, 0.30).toString()
      ctx.lineWidth = 1.2
      ctx.stroke()

      // --- TX area -----------------------------------------------------
      var grad = ctx.createLinearGradient(0, padTop, 0, padTop + plotH)
      grad.addColorStop(0, Util.alpha(root.accent, 0.42).toString())
      grad.addColorStop(1, Util.alpha(root.accent, 0.02).toString())

      ctx.beginPath()
      ctx.moveTo(x0, padTop + plotH)
      for (var i = 0; i < n; i++) ctx.lineTo(x0 + i * stepX, yFor(root.txSamples[i]))
      ctx.lineTo(x0 + (n - 1) * stepX, padTop + plotH)
      ctx.closePath()
      ctx.fillStyle = grad
      ctx.fill()

      ctx.beginPath()
      for (var k = 0; k < n; k++) {
        var px = x0 + k * stepX, py = yFor(root.txSamples[k])
        k === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py)
      }
      ctx.strokeStyle = accentStr
      ctx.lineWidth = 1.8
      ctx.lineJoin = "round"
      ctx.stroke()

      // --- peak marker --------------------------------------------------
      if (root.windowPeak > 0) {
        var peakY = yFor(root.windowPeak)
        ctx.setLineDash([3, 3])
        ctx.strokeStyle = Util.alpha(root.accent, 0.55).toString()
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(0, peakY)
        ctx.lineTo(w, peakY)
        ctx.stroke()
        ctx.setLineDash([])

        ctx.fillStyle = Util.alpha(root.foreground, 0.70).toString()
        ctx.font = "10px '" + root.fontFamily + "'"
        ctx.fillText("peak " + root.humanRate(root.windowPeak), 4, Math.max(10, peakY - 3))
      }

      // --- window label ---------------------------------------------------
      ctx.fillStyle = Util.alpha(root.foreground, 0.40).toString()
      ctx.font = "10px '" + root.fontFamily + "'"
      ctx.fillText("−" + root.capacity + "s", 2, h - 3)
      var lbl = "now"
      ctx.fillText(lbl, w - ctx.measureText(lbl).width - 2, h - 3)
    }
  }

  // Live readout. Text, not canvas, so it re-renders only when the value
  // actually changes.
  Row {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: 4
    anchors.topMargin: 2
    spacing: Style.space(6)

    // Breathing pip: the only continuously animated thing in this component,
    // and it is scene-graph opacity, so it costs no repaints.
    Rectangle {
      width: 6; height: 6; radius: 3
      anchors.verticalCenter: parent.verticalCenter
      color: root.accent
      visible: root.active
      SequentialAnimation on opacity {
        running: root.active
        loops: Animation.Infinite
        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
      }
    }

    Text {
      text: "↑ " + root.humanRate(root.txNow)
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
    Text {
      text: "↓ " + root.humanRate(root.rxNow)
      color: Util.alpha(root.foreground, 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
