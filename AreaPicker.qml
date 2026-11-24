import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: pickerOverlay
  required property var widget
  required property var strings
  required property real listX
  required property real listY
  required property real listWidth
  property alias searchField: field

  signal closeRequested()
  signal pickRequested(int index)
  signal removeRequested(int index)
  signal editRequested(int index)
  signal beginDragRequested(int index, real pitch)
  signal moveDragRequested(real offset)
  signal releaseDragRequested()
  signal commitDragRequested()


  component Label: Text {
    textFormat: Text.PlainText
    color: widget.dimColor
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  component Cell: Label {
    color: widget.textColor
    font.pixelSize: Style.font.body
  }

  component Drawing: Shape {
    property alias path: svg.path
    property alias stroke: shapePath.strokeColor
    property alias strokeWidth: shapePath.strokeWidth
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      id: shapePath
      fillColor: "transparent"
      strokeColor: widget.textColor
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { id: svg }
    }
  }

  anchors.fill: parent
  visible: widget.picking

    MouseArea {
      visible: widget.picking
      anchors.fill: parent
      onClicked: pickerOverlay.closeRequested()
    }

    Rectangle {
      id: list
      visible: widget.picking
      x: listX
      y: listY
      width: listWidth
      height: rows.implicitHeight + 2 * border.width
      color: widget.backgroundColor
      border.width: Math.max(1, Style.space(2))
      border.color: Commons.Color.accent

      Column {
        id: rows
        x: list.border.width
        y: list.border.width
        width: list.width - 2 * list.border.width

        Item {
          id: searchRow
          width: parent.width
          height: Style.spacing.popupRowHeight + Style.spacing.controlPaddingX

          Label {
            visible: field.text === ""
            x: Style.spacing.rowPaddingX
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("search")
            font.pixelSize: Style.font.body
          }
          TextInput {
            id: field
            x: Style.spacing.rowPaddingX
            width: parent.width - 2 * Style.spacing.rowPaddingX
            anchors.verticalCenter: parent.verticalCenter
            color: widget.textColor
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            selectionColor: Style.selectionFill
            clip: true
            onTextEdited: {
              widget.cursor = -1
              widget.filter(text)
            }
            Keys.onPressed: function(event) { event.accepted = widget.pickerKey(event, text) }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(widget.textColor.r, widget.textColor.g, widget.textColor.b, 0.10) }

        Repeater {
          model: widget.choices
          Rectangle {
            id: row
            required property var modelData
            required property int index
            width: rows.width
            height: modelData.detail === "" ? Style.spacing.popupRowHeight : Style.spacing.popupRowHeight + Style.spacing.rowPaddingX
            readonly property bool dragged: index === widget.dragFrom
            z: dragged ? 2 : 0
            opacity: dragged ? 0.9 : 1
            transform: Translate {
              y: widget.rowShift(row.index)
              // The dragged row follows the pointer one-to-one; the others ease aside.
              Behavior on y {
                enabled: !row.dragged
                NumberAnimation { duration: Style.duration(130); easing.type: Easing.OutCubic }
              }
            }
            // The dragged row is solid, so the rows it passes do not show through it.
            color: dragged ? Qt.tint(widget.backgroundColor, Style.hoverFill)
              : index === widget.cursor ? Style.hoverFill
              : modelData.editable && modelData.title === widget.areaName ? Style.selectedFill
              : "transparent"

            MouseArea {
              property real pressY: 0
              property bool armed: false
              anchors.fill: parent
              hoverEnabled: true
              preventStealing: true
              cursorShape: row.dragged ? Qt.ClosedHandCursor
                : widget.canDrag(row.index) ? Qt.OpenHandCursor : Qt.PointingHandCursor
              // Measured in the column, which does not move; the row slides with the drag.
              function pointerY(mouse) { return mapToItem(rows, 0, mouse.y).y }
              // The mouse and the keyboard share one cursor, as in Omarchy.
              onContainsMouseChanged: if (containsMouse && widget.dragFrom < 0) widget.cursor = row.index
              onPressed: function(mouse) {
                pressY = pointerY(mouse)
                armed = false
              }
              onPositionChanged: function(mouse) {
                if (!pressed || !widget.canDrag(row.index)) return
                var dy = pointerY(mouse) - pressY
                // A few pixels of slack, so a click is never a reorder.
                if (!armed) {
                  if (Math.abs(dy) < Style.space(4)) return
                  armed = true
                  pickerOverlay.beginDragRequested(row.index, row.height)
                }
                pickerOverlay.moveDragRequested(dy)
              }
              onReleased: {
                if (armed) pickerOverlay.releaseDragRequested()
                else pickerOverlay.pickRequested(row.index)
                armed = false
              }
              onCanceled: {
                armed = false
                pickerOverlay.commitDragRequested()
              }
            }

            Column {
              x: Style.spacing.rowPaddingX
              width: parent.width - 2 * Style.spacing.rowPaddingX - Style.space(48)
              anchors.verticalCenter: parent.verticalCenter
              Cell { width: parent.width; elide: Text.ElideRight; text: row.modelData.title }
              Label {
                visible: row.modelData.detail !== ""
                width: parent.width
                elide: Text.ElideRight
                text: row.modelData.detail
                font.pixelSize: Style.font.caption
              }
            }

            Item {
              visible: row.modelData.editable && row.index === widget.cursor
              x: parent.width - Style.spacing.rowPaddingX - width - (row.modelData.removable ? Style.space(24) : 0)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(20)
              height: Style.space(20)
              Drawing {
                anchors.centerIn: parent
                width: 11
                height: 11
                strokeWidth: 1.2
                stroke: pencil.containsMouse ? widget.textColor : widget.dimColor
                path: "M 1 10 L 1.5 7.5 L 8 1 L 10 3 L 3.5 9.5 Z M 6.5 2.5 L 8.5 4.5"
              }
              MouseArea {
                id: pencil
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: pickerOverlay.editRequested(row.index)
              }
            }

            // The × of Omarchy's world clock, without its circle, only on the row
            // under the cursor. The 20 px box is there to be easy to hit.
            Item {
              visible: row.modelData.removable && row.index === widget.cursor
              x: parent.width - Style.spacing.rowPaddingX - width
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(20)
              height: Style.space(20)
              Label {
                anchors.centerIn: parent
                text: "×"
                color: cross.containsMouse ? widget.textColor : widget.dimColor
                font.pixelSize: Style.font.title
              }
              MouseArea {
                id: cross
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: pickerOverlay.removeRequested(row.index)
              }
            }
          }
        }

        Item {
          visible: widget.searching || widget.choices.length === 0
          width: parent.width
          height: Style.spacing.popupRowHeight
          Label {
            x: Style.spacing.rowPaddingX
            width: parent.width - 2 * Style.spacing.rowPaddingX
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            font.pixelSize: Style.font.body
            text: widget.searching ? strings.t("searching")
              : field.text === "" ? strings.t("noAreasShort")
              : strings.t("noMatches")
          }
        }
      }
    }
}
