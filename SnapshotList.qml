import QtQuick
import qs.Commons
import qs.Ui

// Snapshot browser.
//
// Two tiers on purpose:
//
//   Local  — every snapshot id the log has seen, with the date and size of the
//            run that produced it. Instant, unprivileged, always available.
//   Repo   — the authoritative list straight from Backblaze, with paths, tags
//            and hostname. Requires the repository password from root-only
//            /root/.restic-env, so it is behind an explicit button and a polkit
//            prompt. Never fetched on a timer: a bar widget should not be
//            reaching across the network to a paid object store on its own, and
//            it should certainly not hold credentials to do so.
//
// Expanding a repo snapshot lists its top-level paths via `restic ls`, which is
// another round trip and so is likewise only ever user-initiated.
Item {
  id: root

  property var runs: []            // local: [{snapshot, ts, added, dur, ok}]
  property var repoSnapshots: []   // remote: restic snapshots --json
  property bool loading: false
  property string errorText: ""
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  property string expandedId: ""
  property var pathsById: ({})

  signal loadRepoRequested()
  signal listPathsRequested(string id)

  function humanBytes(b) {
    b = Number(b) || 0
    if (b < 1048576) return (b / 1024).toFixed(0) + " KiB"
    if (b < 1073741824) return (b / 1048576).toFixed(0) + " MiB"
    return (b / 1073741824).toFixed(2) + " GiB"
  }

  // Newest first — the one you would actually restore from is at the top.
  readonly property var localRows: {
    var out = []
    for (var i = runs.length - 1; i >= 0; i--) {
      if (runs[i].snapshot) out.push(runs[i])
    }
    return out.slice(0, 12)
  }

  implicitHeight: col.implicitHeight

  Column {
    id: col
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: root.repoSnapshots.length > 0 ? root.repoSnapshots : root.localRows

      Item {
        id: snapRow
        required property var modelData
        width: col.width
        implicitHeight: rowCol.implicitHeight + Style.space(6)

        readonly property bool isRepo: root.repoSnapshots.length > 0
        readonly property string sid: isRepo
          ? String(modelData.short_id || String(modelData.id || "").substring(0, 8))
          : String(modelData.snapshot || "")
        readonly property bool expanded: root.expandedId === sid && isRepo

        Rectangle {
          anchors.fill: parent
          radius: Style.space(4)
          color: hover.hovered ? Util.alpha(root.foreground, 0.06) : "transparent"
        }
        HoverHandler { id: hover }
        TapHandler {
          enabled: snapRow.isRepo
          onTapped: {
            if (root.expandedId === snapRow.sid) { root.expandedId = ""; return }
            root.expandedId = snapRow.sid
            if (!root.pathsById[snapRow.sid]) root.listPathsRequested(snapRow.sid)
          }
        }

        Column {
          id: rowCol
          x: Style.space(6)
          width: parent.width - Style.space(12)
          y: Style.space(3)
          spacing: 1

          Row {
            spacing: Style.space(8)
            Text {
              text: snapRow.sid || "········"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              text: {
                var m = snapRow.modelData
                if (snapRow.isRepo)
                  return String(m.time || "").substring(0, 16).replace("T", " ")
                return m.ts > 0 ? Qt.formatDateTime(new Date(m.ts * 1000), "yyyy-MM-dd hh:mm") : ""
              }
              color: Util.alpha(root.foreground, 0.55)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              visible: !snapRow.isRepo
              text: root.humanBytes(snapRow.modelData.added) + " added"
              color: Util.alpha(root.foreground, 0.55)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              visible: snapRow.isRepo && !!(snapRow.modelData.tags)
              text: snapRow.isRepo && snapRow.modelData.tags
                ? String(snapRow.modelData.tags.join(", ")) : ""
              color: Util.alpha(root.foreground, 0.42)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            visible: snapRow.isRepo && snapRow.expanded
            width: rowCol.width
            text: {
              var p = root.pathsById[snapRow.sid]
              if (p === undefined) return "loading paths…"
              if (!p || p.length === 0) return "no paths returned"
              return p.join("    ")
            }
            color: Util.alpha(root.foreground, 0.60)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }
        }
      }
    }

    Text {
      visible: root.localRows.length === 0 && root.repoSnapshots.length === 0
      text: "No snapshots recorded yet"
      color: Util.alpha(root.foreground, 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Row {
      spacing: Style.space(8)

      PanelActionButton {
        enabled: !root.loading
        iconText: "󰅢"
        tooltipText: "Fetch the authoritative snapshot list from the repository (asks for authentication)"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.loadRepoRequested()
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.loading ? "Querying repository…"
             : root.errorText !== "" ? root.errorText
             : root.repoSnapshots.length > 0
               ? root.repoSnapshots.length + " snapshots in repo · click one for paths"
               : "Load from repository (needs auth)"
        color: root.errorText !== "" ? "#ff4d4d" : Util.alpha(root.foreground, 0.60)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
