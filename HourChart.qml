import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: chartView
  required property var widget
  required property var chart
  required property color tint
  readonly property var panel: widget.panel
  readonly property int hovered: widget.hovered
  readonly property int hours: widget.hours
  readonly property int axis: widget.axis
  readonly property color textColor: widget.textColor
  readonly property color dimColor: widget.dimColor
  readonly property color chartColor: widget.chartColor
  readonly property color gridColor: widget.gridColor
  readonly property color freezingColor: widget.freezingColor
  readonly property color rainColor: widget.rainColor
  readonly property color snowColor: widget.snowColor
  readonly property color iceColor: widget.iceColor

  function toneColor(tone, tint) {
    if (tone === "snow") return snowColor
    if (tone === "ice") return iceColor
    return tint
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: chartView.dimColor
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  component Trace: Shape {
    property alias path: svg.path
    property alias fill: shapePath.fillColor
    property alias stroke: shapePath.strokeColor
    property alias strokeWidth: shapePath.strokeWidth
    visible: svg.path !== ""
    width: chartView.panel ? chartView.panel.chart_width : 1
    height: chartView.panel ? chartView.panel.chart_height : 1
    preferredRendererType: Shape.CurveRenderer
    transform: Scale {
      xScale: chartView.panel ? parent.width / chartView.panel.chart_width : 1
      yScale: chartView.panel ? parent.height / chartView.panel.chart_height : 1
    }
    ShapePath {
      id: shapePath
      fillColor: "transparent"
      strokeColor: "transparent"
      strokeWidth: 0
      PathSvg { id: svg }
    }
  }

  width: parent.width
  height: Style.space(94)

  Item {
    id: plot
    property var chart
    property color tint
    chart: chartView.chart
    tint: chartView.tint
    width: parent.width
    height: Style.space(94)

    Row {
      spacing: Style.space(10)
      Repeater {
        model: plot.chart ? plot.chart.legend : []
        Label { text: modelData.text; color: toneColor(modelData.tone, plot.tint) }
      }
    }

    Repeater {
      model: plot.chart ? plot.chart.ticks : []
      Label {
        x: 0
        y: area.y + area.height * modelData.position - height / 2
        width: axis - Style.space(6)
        horizontalAlignment: Text.AlignRight
        text: modelData.text
        color: plot.chart.zero !== null && plot.chart.zero !== undefined && modelData.text === "0" ? textColor : dimColor
      }
    }

    Rectangle {
      id: area
      x: axis
      y: Style.space(20)
      width: parent.width - axis
      height: parent.height - Style.space(26)
      color: chartColor

      Repeater {
        model: plot.chart ? plot.chart.ticks : []
        Rectangle { y: area.height * modelData.position; width: area.width; height: 1; color: gridColor }
      }
      // Freezing, a thin red line so the side of 0 °C shows at a glance.
      Rectangle {
        visible: !!plot.chart && plot.chart.zero !== null && plot.chart.zero !== undefined
        y: plot.chart && plot.chart.zero !== null && plot.chart.zero !== undefined ? area.height * plot.chart.zero : 0
        width: area.width
        height: 1
        color: freezingColor
      }
      Repeater {
        model: panel ? panel.marks : []
        Rectangle {
          x: area.width * modelData.position
          width: 1
          height: area.height
          color: modelData.midnight ? dimColor : gridColor
        }
      }
      Trace { path: plot.chart ? plot.chart.rain : ""; fill: rainColor }
      Trace { path: plot.chart ? plot.chart.snow : ""; fill: snowColor }
      Trace { path: plot.chart ? plot.chart.ice : ""; fill: iceColor }
      Trace { path: plot.chart ? plot.chart.line : ""; stroke: plot.tint; strokeWidth: 2 }
      Rectangle {
        visible: hovered >= 0
        x: area.width * (hovered + 0.5) / Math.max(1, hours)
        width: 1
        height: area.height
        color: textColor
      }
    }
  }
}
