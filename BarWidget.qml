import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Peakcast in the bar: the summit temperature of an area, and on click a card with
// its mountain forecast. The numbers come from the peakcast engine, run as a
// command; this widget only shows the JSON it prints.
BarWidget {
  id: root
  moduleName: "io.github.alrubearb-sys.peakcast"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // md-summit from Nerd Fonts, written as the built-in widgets write their icons.
  readonly property string icon: "󰞆"
  readonly property int refreshMinutes: 30

  property var areas: []
  property int selected: 0
  property var report: null
  property string problem: ""
  property bool missing: false
  property bool popupOpen: false
  property real updatedAt: 0

  readonly property var summitNow: report ? currentHour(report.summit) : null
  readonly property var baseNow: report && report.base ? currentHour(report.base) : null

  function close() { popupOpen = false }

  // peakcast is often in ~/.local/bin, which the shell's PATH may lack. The
  // arguments go as "$@", never into the script text.
  function engine(args) {
    return ["sh", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec peakcast \"$@\"", "peakcast"].concat(args)
  }

  function loadAreas() {
    areasProcess.running = true
  }

  function fetch() {
    if (areas.length === 0 || reportProcess.running) return
    reportProcess.command = engine(["--json", "--", areas[selected]])
    reportProcess.running = true
  }

  function select(step) {
    if (areas.length < 2) return
    selected = (selected + step + areas.length) % areas.length
    report = null
    fetch()
  }

  function readAreas(text) {
    try {
      areas = JSON.parse(text).map(function(area) { return String(area.name) })
    } catch (error) {
      areas = []
    }
    if (selected >= areas.length) selected = 0
    fetch()
  }

  function readReport(text) {
    try {
      report = JSON.parse(text)
      problem = ""
      updatedAt = Date.now()
    } catch (error) {
      problem = "cannot read the answer of peakcast"
    }
  }

  // The last hour that has started, as the Mac panel shows.
  function currentHour(forecast) {
    var now = Date.now() / 1000
    var found = null
    for (var i = 0; i < forecast.hours.length && forecast.hours[i].time <= now; i++)
      found = forecast.hours[i]
    return found
  }

  // The wind at the height of the summit when the forecast has it.
  function wind(hour) {
    var kmh = hour.high_wind_kmh !== null && hour.high_wind_kmh !== undefined ? hour.high_wind_kmh : hour.wind_kmh
    return Math.round(kmh) + " km/h"
  }

  // "-0" reads oddly: adding 0 turns it into 0.
  function degrees(value) {
    return (Math.round(value) + 0) + " °C"
  }

  function meters(value) {
    return value === null || value === undefined ? "-" : Math.round(value) + " m"
  }

  function clock(time, offset) {
    var date = new Date((time + offset) * 1000)
    function two(number) { return number < 10 ? "0" + number : String(number) }
    return two(date.getUTCHours()) + ":" + two(date.getUTCMinutes())
  }

  function daylight(forecast) {
    var offset = forecast.utc_offset_seconds
    var today = Math.floor((Date.now() / 1000 + offset) / 86400)
    for (var i = 0; i < forecast.days.length; i++) {
      var day = forecast.days[i]
      if (Math.floor((day.sunrise + offset) / 86400) === today)
        return clock(day.sunrise, offset) + " - " + clock(day.sunset, offset)
    }
    return ""
  }

  // "summit" only makes sense with a base below it; a single point says what it is.
  function pointLabel() {
    if (report.base) return strings.t("summit")
    if (report.kind) return String(report.kind).replace(/_/g, " ")
    return strings.t("elevation")
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  Component.onCompleted: loadAreas()

  Timer {
    interval: root.refreshMinutes * 60 * 1000
    running: root.areas.length > 0
    repeat: true
    onTriggered: root.fetch()
  }

  Process {
    id: areasProcess
    command: root.engine(["areas", "--json"])
    stdout: StdioCollector { onStreamFinished: root.readAreas(text) }
    // 127: the shell did not find peakcast.
    onExited: function(code) { root.missing = code === 127 }
  }

  Process {
    id: reportProcess
    stdout: StdioCollector { onStreamFinished: if (text !== "") root.readReport(text) }
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") root.problem = text.trim() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.summitNow ? root.icon + " " + (Math.round(root.summitNow.temperature_c) + 0) + "°" : root.icon
    tooltipText: root.popupOpen ? "" : strings.t("tooltip")
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) {
        root.loadAreas()
        return
      }
      root.popupOpen = !root.popupOpen
      if (root.popupOpen) root.loadAreas()
    }
  }

  // Text from the engine is shown as plain text, never as markup.
  component Label: Text {
    textFormat: Text.PlainText
    color: Commons.Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  component Dim: Label {
    color: Qt.darker(Commons.Color.popups.text, 1.5)
    font.pixelSize: Style.font.bodySmall
  }

  component Arrow: Label {
    signal clicked()
    visible: root.areas.length > 1
    font.pixelSize: Style.font.title
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.clicked()
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      width: parent.width
      spacing: Style.space(8)

      Label {
        visible: root.missing
        width: parent.width
        wrapMode: Text.WordWrap
        text: strings.t("missing") + "\n" + strings.t("install")
      }

      Label {
        visible: !root.missing && root.areas.length === 0
        width: parent.width
        wrapMode: Text.WordWrap
        text: strings.t("noAreas")
      }

      Row {
        visible: root.areas.length > 0
        width: parent.width
        spacing: Style.space(8)

        Arrow { text: "‹"; onClicked: root.select(-1) }
        Label {
          width: parent.width - Style.space(80) - daylightText.implicitWidth
          elide: Text.ElideRight
          text: root.areas.length > 0 ? root.areas[root.selected] : ""
          color: Commons.Color.accent
          font.pixelSize: Style.font.heading
        }
        Arrow { text: "›"; onClicked: root.select(1) }
        Label {
          id: daylightText
          anchors.verticalCenter: parent.verticalCenter
          text: root.report ? root.daylight(root.report.summit) : ""
        }
      }

      Label {
        visible: root.problem !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        color: Commons.Color.urgent
        text: root.problem
      }

      Dim {
        visible: root.areas.length > 0 && !root.report && root.problem === ""
        text: strings.t("loading")
      }

      Grid {
        visible: root.summitNow !== null
        columns: 3
        columnSpacing: Style.space(18)
        rowSpacing: Style.space(4)

        Dim { text: root.report ? root.pointLabel() : "" }
        Dim { text: strings.t("temperature") }
        Dim { text: strings.t("wind") }

        Label { text: root.report ? root.meters(root.report.summit.point.elevation) : "" }
        Label { text: root.summitNow ? root.degrees(root.summitNow.temperature_c) : "" }
        Label { text: root.summitNow ? root.wind(root.summitNow) : "" }

        Dim { visible: root.baseNow !== null; text: strings.t("base") }
        Dim { visible: root.baseNow !== null; text: "" }
        Dim { visible: root.baseNow !== null; text: "" }

        Label { visible: root.baseNow !== null; text: root.report && root.report.base ? root.meters(root.report.base.point.elevation) : "" }
        Label { visible: root.baseNow !== null; text: root.baseNow ? root.degrees(root.baseNow.temperature_c) : "" }
        Label { visible: root.baseNow !== null; text: root.baseNow ? root.wind(root.baseNow) : "" }
      }

      Grid {
        visible: root.summitNow !== null
        columns: 2
        columnSpacing: Style.space(18)
        rowSpacing: Style.space(4)

        Dim { text: strings.t("snowLine") }
        Dim { text: strings.t("freezingLevel") }
        Label { text: root.summitNow ? root.meters(root.summitNow.snow_line_m) : "" }
        Label { text: root.summitNow ? root.meters(root.summitNow.freezing_level_m) : "" }
      }

      Dim {
        visible: root.updatedAt > 0
        text: strings.t("updated").arg(new Date(root.updatedAt).toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), "hh:mm")) + " · " + strings.t("credit")
        font.pixelSize: Style.font.caption
      }
    }
  }
}
