import QtQuick
import qs.Commons

// A labelled proportional bar, used twice in the panel:
//
//   Dedup   — how much of what restic ADDED actually had to be STORED after
//             compression and deduplication. A short filled portion is good
//             news; it means most of the change was redundant.
//   Churn   — how much of the tree was new/changed versus untouched. A tiny
//             coloured sliver on a huge bar is what a healthy incremental
//             backup looks like.
//
// Pure scene-graph items — no Canvas at all, so nothing to repaint. The fill
// width animates when the numbers change, which reads as the bar filling in.
Item {
  id: root

  property string label: ""
  property var segments: []      // [{value, color, name}]
  property string trailing: ""   // right-aligned summary text
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  readonly property real total: {
    var t = 0
    for (var i = 0; i < segments.length; i++) t += Math.max(0, segments[i].value || 0)
    return t
  }

  implicitHeight: labelRow.implicitHeight + Style.space(6) + Style.space(10) + legend.implicitHeight

  Item {
    id: labelRow
    width: parent.width
    implicitHeight: Math.max(nameText.implicitHeight, trailText.implicitHeight)

    Text {
      id: nameText
      anchors.left: parent.left
      text: root.label
      color: Util.alpha(root.foreground, 0.65)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.0
    }
    Text {
      id: trailText
      anchors.right: parent.right
      text: root.trailing
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Rectangle {
    id: track
    anchors.top: labelRow.bottom
    anchors.topMargin: Style.space(6)
    width: parent.width
    height: Style.space(10)
    radius: height / 2
    color: Util.alpha(root.foreground, 0.10)
    clip: true

    Row {
      anchors.fill: parent
      spacing: 0

      Repeater {
        model: root.segments

        Rectangle {
          required property var modelData
          height: track.height
          width: root.total > 0 ? track.width * (Math.max(0, modelData.value) / root.total) : 0
          color: modelData.color
          Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        }
      }
    }
  }

  Row {
    id: legend
    anchors.top: track.bottom
    anchors.topMargin: Style.space(4)
    spacing: Style.space(10)

    Repeater {
      model: root.segments

      Row {
        required property var modelData
        spacing: Style.space(4)
        visible: (modelData.name || "") !== ""

        Rectangle {
          width: 6; height: 6; radius: 1.5
          anchors.verticalCenter: parent.verticalCenter
          color: modelData.color
        }
        Text {
          text: modelData.name
          color: Util.alpha(root.foreground, 0.60)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
