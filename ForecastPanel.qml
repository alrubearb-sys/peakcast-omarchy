import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: forecast
  required property var widget
  required property var strings

  component Label: Text {
    textFormat: Text.PlainText
    color: widget.dimColor
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  component Value: Label {
    color: widget.textColor
    font.pixelSize: Style.font.title
  }

  component Cell: Label {
    color: widget.textColor
    font.pixelSize: Style.font.body
  }

  component Separator: Rectangle {
    width: parent.width
    height: 1
    color: widget.gridColor
  }

  component Pair: Column {
    property alias label: top.text
    property alias value: bottom.text
    property alias valueColor: bottom.color
    Label { id: top }
    Value { id: bottom }
  }

  // Omarchy's control chrome: a border of the text colour and a faint fill that
  // grows on hover and press. Corners stay square, as in Omarchy's default.
  component Control: Rectangle {
    id: control
    property bool lit: false
    readonly property alias hovered: touch.containsMouse
    signal clicked()
    color: touch.pressed ? Style.pressedFill : touch.containsMouse || lit ? Style.hoverFill : Style.normalFill
    border.width: Style.normalBorderWidth
    border.color: touch.containsMouse || lit ? Style.hoverBorderColor : Style.normalBorderColor
    MouseArea {
      id: touch
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: control.clicked()
    }
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


  KeyboardPanel {
    id: card
    anchorItem: widget
    bar: widget.bar
    owner: widget
    open: widget.popupOpen
    focusTarget: card.loadedContent
    padding: Style.spacing.panelPadding
    // Like the Mac window: 440 wide with border and padding, 400 for the content.
    contentWidth: card.fittedContentWidth(Style.space(440))
    contentHeight: card.fittedContentHeight(card.loadedContentHeight)

    // Built the first time the panel opens, so a closed panel holds no memory.
    content: FocusScope {
      id: body
      implicitHeight: column.implicitHeight
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) widget.close()
        else if (event.key === Qt.Key_Left) widget.step(-1)
        else if (event.key === Qt.Key_Right) widget.step(1)
        else return
        event.accepted = true
      }

      Connections {
        target: widget
        function onPickingChanged() {
          if (widget.picking) {
            picker.searchField.text = ""
            Qt.callLater(picker.searchField.forceActiveFocus)
          } else {
            body.forceActiveFocus()
          }
        }
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.spacing.rowGap

        Label {
          visible: widget.missing
          width: parent.width
          wrapMode: Text.WordWrap
          color: widget.textColor
          text: strings.t("missing") + "\n" + strings.t("install")
        }

        Label {
          visible: !widget.missing && widget.areas.length === 0
          width: parent.width
          wrapMode: Text.WordWrap
          color: widget.textColor
          text: strings.t("noAreas")
        }

        Row {
          id: header
          visible: widget.areas.length > 0
          width: parent.width
          spacing: Style.spacing.rowGap

          // Omarchy's dropdown trigger: control chrome, the current area and a chevron.
          Control {
            id: trigger
            width: header.width - mapButton.width - daylightText.width - 2 * header.spacing
            height: Style.spacing.controlHeight
            lit: widget.picking
            onClicked: widget.picking ? widget.closePicker() : widget.openPicker()

            Label {
              x: Style.spacing.controlPaddingX
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - x - chevron.width - 2 * Style.spacing.controlGap
              elide: Text.ElideRight
              text: widget.areaName
              color: Commons.Color.accent
              font.pixelSize: Style.font.heading
            }
            Drawing {
              id: chevron
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.controlGap
              anchors.verticalCenter: parent.verticalCenter
              width: 10
              height: 6
              strokeWidth: 1.5
              path: "M 1 1 L 5 5 L 9 1"
            }
          }

          // A square control with a folded map drawn on it, as on the Mac.
          Control {
            id: mapButton
            width: Style.spacing.controlHeight
            height: Style.spacing.controlHeight
            onClicked: widget.openMap()

            Drawing {
              anchors.centerIn: parent
              width: 16
              height: 14
              strokeWidth: 1.25
              path: "M 1 2 L 5.5 1 L 10.5 2 L 15 1 L 15 12 L 10.5 13 L 5.5 12 L 1 13 Z M 5.5 1 L 5.5 12 M 10.5 2 L 10.5 13"
            }
          }

          Label {
            id: daylightText
            anchors.verticalCenter: parent.verticalCenter
            text: widget.panel ? widget.panel.daylight : ""
            color: widget.sunColor
            font.pixelSize: Style.font.body
          }
        }

        Separator { }

        Label {
          visible: widget.problem !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          color: widget.iceColor
          font.pixelSize: Style.font.body
          text: widget.problem
        }

        Label {
          visible: widget.areas.length > 0 && !widget.panel && widget.problem === ""
          text: strings.t("loading")
        }

        Column {
          visible: widget.panel !== null
          opacity: widget.waiting ? 0.5 : 1
          width: parent.width
          spacing: Style.spacing.rowGap

          Repeater {
            model: widget.panel ? widget.panel.spots : []
            Row {
              Pair { width: Style.space(92); label: modelData.label; value: modelData.height }
              Pair { width: Style.space(124); label: strings.t("sky"); value: modelData.sky }
              Pair { width: Style.space(76); label: strings.t("temperature"); value: modelData.temperature; valueColor: widget.temperatureColor }
              Pair { label: strings.t("wind"); value: modelData.wind; valueColor: widget.windColor }
            }
          }

          Row {
            Pair { width: Style.space(92); label: strings.t("snowLine"); value: widget.panel ? widget.panel.snow_line : "" }
            Pair { width: Style.space(124); label: strings.t("freezingLevel"); value: widget.panel ? widget.panel.freezing_level : "" }
            Pair { label: strings.t("snowDepth"); value: widget.panel ? widget.panel.snow_depth : "" }
          }

          Separator { }

          Label {
            text: widget.hovered >= 0 && widget.panel ? widget.panel.readings[widget.hovered] : strings.t("next")
            color: widget.hovered >= 0 ? widget.textColor : widget.dimColor
          }

          Item {
            width: parent.width
            height: Style.space(306)

            HourChart {
              y: 0
              chart: widget.panel ? widget.panel.temperature : null
              widget: forecast.widget
              tint: widget.temperatureColor
            }
            HourChart {
              y: Style.space(96)
              chart: widget.panel ? widget.panel.wind : null
              widget: forecast.widget
              tint: widget.windColor
            }
            HourChart {
              y: Style.space(192)
              chart: widget.panel ? widget.panel.precipitation : null
              widget: forecast.widget
              tint: widget.rainColor
            }

            Repeater {
              model: widget.panel ? widget.panel.marks : []
              Label {
                x: widget.axis + (parent.width - widget.axis) * modelData.position - width / 2
                y: Style.space(288)
                text: modelData.text
                color: modelData.midnight ? widget.textColor : widget.dimColor
              }
            }

            MouseArea {
              x: widget.axis
              width: parent.width - widget.axis
              height: parent.height
              hoverEnabled: true
              onPositionChanged: function(mouse) {
                var index = Math.min(widget.hours - 1, Math.max(0, Math.floor(mouse.x / width * widget.hours)))
                if (index !== widget.hovered) widget.hovered = index
              }
              onExited: widget.hovered = -1
            }
          }

          Separator { }

          Row {
            Label { width: Style.space(44); text: strings.t("day") }
            Label { width: Style.space(104); text: strings.t("sky") }
            Label { width: Style.space(78); text: strings.t("dayTemperature") }
            Label { width: Style.space(66); text: strings.t("windMax") }
            Label { width: Style.space(56); text: strings.t("sun") }
            Label { width: column.width - Style.space(348); horizontalAlignment: Text.AlignRight; text: strings.t("snow") }
          }

          Column {
            spacing: Style.spacing.labelGap
            Repeater {
              model: widget.panel ? widget.panel.days : []
              Row {
                Cell { width: Style.space(44); text: modelData.name }
                Cell { width: Style.space(104); text: modelData.sky; elide: Text.ElideRight }
                Cell { width: Style.space(78); text: modelData.temperature; color: widget.temperatureColor }
                Cell { width: Style.space(66); text: modelData.wind; color: widget.windColor }
                Cell { width: Style.space(56); text: modelData.sun; color: widget.sunColor }
                Cell { width: column.width - Style.space(348); horizontalAlignment: Text.AlignRight; text: modelData.snow; color: widget.snowColor }
              }
            }
          }
        }

        Item {
          visible: widget.updatedAt > 0
          width: parent.width
          height: refresh.implicitHeight

          Label {
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("updated").arg(new Date(widget.updatedAt).toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), "hh:mm"))
          }
          Button {
            id: refresh
            anchors.right: parent.right
            bordered: true
            text: strings.t("refresh")
            onClicked: widget.refresh()
          }
        }

        // The source of the data and, when there is one, the update link: one faint
        // line at the very end, there when wanted and never in the way.
        Item {
          visible: widget.panel !== null || widget.newVersion !== ""
          width: parent.width
          height: credits.implicitHeight

          Label {
            id: credits
            text: widget.panel ? widget.panel.credits : ""
            font.pixelSize: Style.font.caption
            opacity: 0.4
          }
          Label {
            visible: widget.newVersion !== ""
            anchors.right: parent.right
            text: strings.t("update").arg(widget.newVersion)
            font.pixelSize: Style.font.caption
            opacity: updateArea.containsMouse ? 0.9 : 0.4

            MouseArea {
              id: updateArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: widget.update()
            }
          }
        }
      }

      AreaPicker {
        id: picker
        widget: forecast.widget
        strings: forecast.strings
        listX: header.x + trigger.x
        listY: header.y + trigger.height + Style.spacing.labelGap
        listWidth: trigger.width
        onCloseRequested: widget.closePicker()
        onPickRequested: function(index) { widget.pick(index) }
        onRemoveRequested: function(index) { widget.remove(index) }
        onEditRequested: function(index) { widget.edit(index) }
        onBeginDragRequested: function(index, pitch) { widget.beginDrag(index, pitch) }
        onMoveDragRequested: function(offset) { widget.moveDrag(offset) }
        onReleaseDragRequested: widget.releaseDrag()
        onCommitDragRequested: widget.commitDrag()
      }
    }
  }
}
