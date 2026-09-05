import QtQuick
import qs.Commons

// Every completed run in the log as one bar: height is data added to the
// repository, colour intensity is how long it took. Hovering reads out both.
//
// This is the view that answers "is my backup behaving?" at a glance — a row of
// small even bars is a healthy daily delta; a sudden tall bar is the day
// something large landed, and a wide dark bar is a run that dragged.
//
// Painted only when the model or palette changes. Hover feedback is a
// scene-graph Rectangle, not a repaint.
Item {
  id: root

  property var runs: []                // [{added, dur}], oldest first
  property color accent: Color.accent
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  property int hoveredIndex: -1

  readonly property real maxAdded: {
    var m = 0
    for (var i = 0; i < runs.length; i++) if (runs[i].added > m) m = runs[i].added
    return m
  }
  readonly property real maxDur: {
    var m = 0
    for (var i = 0; i < runs.length; i++) if (runs[i].dur > m) m = runs[i].dur
    return m
  }

  function humanBytes(b) {
    b = b || 0
    if (b < 1024) return b + " B"
    if (b < 1048576) return (b / 1024).toFixed(0) + " KiB"
    if (b < 1073741824) return (b / 1048576).toFixed(1) + " MiB"
    return (b / 1073741824).toFixed(2) + " GiB"
  }
  function humanDur(s) {
    s = Math.round(s || 0)
    if (s < 60) return s + "s"
    var m = Math.floor(s / 60), r = s % 60
    if (m < 60) return m + "m " + r + "s"
    return Math.floor(m / 60) + "h " + (m % 60) + "m"
  }

  implicitHeight: Style.space(66)

  Row {
    id: barRow
    anchors.fill: parent
    anchors.bottomMargin: Style.space(14)
    spacing: 2

    Repeater {
      model: root.runs

      Item {
        required property var modelData
        required property int index

        width: Math.max(3, (barRow.width - (root.runs.length - 1) * 2) / Math.max(1, root.runs.length))
        height: barRow.height

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          // Square-root scale: daily deltas differ by orders of magnitude, and
          // a linear axis flattens every normal day into an invisible sliver
          // next to one big backfill.
          height: Math.max(2, parent.height * Math.sqrt(
                    root.maxAdded > 0 ? modelData.added / root.maxAdded : 0))
          radius: 1.5

          // Longer runs read darker/warmer, so duration is legible without a
          // second chart.
          color: {
            var f = root.maxDur > 0 ? Math.min(1, modelData.dur / root.maxDur) : 0
            return Qt.tint(root.accent, Qt.rgba(1, 0.42, 0.2, f * 0.55))
          }
          opacity: root.hoveredIndex === -1 || root.hoveredIndex === index ? 1.0 : 0.35
          Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        HoverHandler {
          onHoveredChanged: root.hoveredIndex = hovered ? index : -1
        }
      }
    }
  }

  Text {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    text: root.runs.length > 0
      ? (root.hoveredIndex >= 0
          ? root.humanBytes(root.runs[root.hoveredIndex].added) + " · " + root.humanDur(root.runs[root.hoveredIndex].dur)
          : root.runs.length + " runs · tallest " + root.humanBytes(root.maxAdded))
      : "No completed runs in the log"
    color: root.hoveredIndex >= 0 ? root.foreground : Util.alpha(root.foreground, 0.55)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
