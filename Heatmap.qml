import QtQuick
import qs.Commons

// A GitHub-contribution-style calendar of backup outcomes.
//
// One cell per day for the trailing window, laid out in week columns with
// weekday rows. Green means every run that day succeeded, with intensity
// scaled by how much data landed; red means at least one run failed; an empty
// outline means no backup ran at all, which is its own kind of bad news and is
// deliberately distinguishable from "ran and succeeded".
//
// Entirely scene-graph Rectangles — no Canvas, nothing to repaint. Hover
// feedback is an opacity binding.
Item {
  id: root

  property var calendar: []       // [{date:"YYYY-MM-DD", runs, ok, added}]
  property int weeks: 14
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  property string hoveredKey: ""

  readonly property real maxAdded: {
    var m = 0
    for (var i = 0; i < calendar.length; i++) if (calendar[i].added > m) m = calendar[i].added
    return m
  }

  // Index the sparse calendar by date so the dense grid can look days up.
  readonly property var byDate: {
    var m = ({})
    for (var i = 0; i < calendar.length; i++) m[calendar[i].date] = calendar[i]
    return m
  }

  // Build a dense day grid ending today, aligned so each column is a week.
  readonly property var grid: {
    var out = []
    var today = new Date()
    today.setHours(12, 0, 0, 0)
    // Walk back to the most recent Sunday so columns line up as weeks.
    var end = new Date(today)
    end.setDate(end.getDate() + (6 - end.getDay()))
    var total = weeks * 7
    for (var i = total - 1; i >= 0; i--) {
      var d = new Date(end)
      d.setDate(end.getDate() - i)
      var key = Qt.formatDate(d, "yyyy-MM-dd")
      out.push({ key: key, future: d > today })
    }
    return out
  }

  function humanBytes(b) {
    b = b || 0
    if (b < 1048576) return (b / 1024).toFixed(0) + " KiB"
    if (b < 1073741824) return (b / 1048576).toFixed(0) + " MiB"
    return (b / 1073741824).toFixed(2) + " GiB"
  }

  implicitHeight: gridRow.implicitHeight + Style.space(16)

  Row {
    id: gridRow
    spacing: 3

    Repeater {
      model: root.weeks

      Column {
        id: weekCol
        required property int index
        // Captured under a distinct name: the inner Repeater's delegate has its
        // own required `index`, which would otherwise shadow this one.
        readonly property int week: index
        spacing: 3

        Repeater {
          model: 7

          Rectangle {
            required property int index
            readonly property var cell: root.grid[weekCol.week * 7 + index]
            readonly property var day: cell ? root.byDate[cell.key] : undefined

            width: 11; height: 11; radius: 2

            color: {
              if (!cell || cell.future) return "transparent"
              if (!day) return Util.alpha(root.foreground, 0.07)
              if (!day.ok) return "#ff4d4d"
              var f = root.maxAdded > 0 ? Math.sqrt(day.added / root.maxAdded) : 0.5
              return Qt.rgba(0.22, 0.83, 0.33, 0.28 + f * 0.72)
            }
            border.width: (cell && !cell.future && !day) ? 1 : 0
            border.color: Util.alpha(root.foreground, 0.12)
            opacity: root.hoveredKey === "" || (cell && root.hoveredKey === cell.key) ? 1.0 : 0.35
            Behavior on opacity { NumberAnimation { duration: 110 } }

            HoverHandler {
              enabled: !!cell && !cell.future
              onHoveredChanged: root.hoveredKey = (hovered && cell) ? cell.key : ""
            }
          }
        }
      }
    }
  }

  Text {
    anchors.top: gridRow.bottom
    anchors.topMargin: Style.space(4)
    text: {
      if (root.hoveredKey !== "") {
        var d = root.byDate[root.hoveredKey]
        if (!d) return root.hoveredKey + " · no backup"
        return root.hoveredKey + " · " + d.runs + (d.runs === 1 ? " run · " : " runs · ")
             + root.humanBytes(d.added) + (d.ok ? "" : " · FAILED")
      }
      var ok = 0, bad = 0
      for (var i = 0; i < root.calendar.length; i++) root.calendar[i].ok ? ok++ : bad++
      return ok + " clean days" + (bad > 0 ? " · " + bad + " with failures" : "") + " · hover a cell"
    }
    color: Util.alpha(root.foreground, 0.60)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
