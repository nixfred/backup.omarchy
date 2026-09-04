import QtQuick
import qs.Commons

// A micro bar-chart of the last N runs, small enough to live inside the bar
// icon. Gives the trend at a glance without opening the panel: a run that
// suddenly towers over its neighbours, or a red bar, is visible from across the
// desk.
//
// Scene-graph Rectangles only — this sits in the bar, which is on the
// compositor's hot path, so it must never rasterise anything.
Item {
  id: root

  property var runs: []            // [{added, ok}], oldest first
  property int count: 7
  property color accent: Color.accent
  property color failColor: "#ff4d4d"

  readonly property var tail: runs.slice(Math.max(0, runs.length - count))
  readonly property real maxAdded: {
    var m = 0
    for (var i = 0; i < tail.length; i++) if (tail[i].added > m) m = tail[i].added
    return m
  }

  visible: tail.length > 0

  Row {
    anchors.fill: parent
    spacing: 1

    Repeater {
      model: root.tail

      Item {
        required property var modelData
        width: Math.max(1, (root.width - (root.tail.length - 1)) / Math.max(1, root.tail.length))
        height: root.height

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          // Square root, same as the big history chart, so one large backfill
          // does not flatten every ordinary day into nothing.
          height: Math.max(1, parent.height * Math.sqrt(
                    root.maxAdded > 0 ? modelData.added / root.maxAdded : 0))
          color: modelData.ok ? root.accent : root.failColor
          opacity: modelData.ok ? 0.85 : 1.0
        }
      }
    }
  }
}
