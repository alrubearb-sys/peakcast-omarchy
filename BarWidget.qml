import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Peakcast in the bar: the icon of the Mac app, and on click the same panel as
// the Mac app. The peakcast engine works everything out (`peakcast panel`) and
// peakcast-map picks the points; this widget only draws and runs them.
BarWidget {
  id: root
  moduleName: "io.github.alrubearb-sys.peakcast"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Width of the tick numbers on the left of the charts.
  readonly property int axis: Style.space(38)

  // Saved areas as `peakcast areas --json` gives them, with their points.
  property var areas: []
  property int selected: 0
  // The area to show once the areas are read again, after saving or editing one.
  property string wanted: ""
  property var panel: null
  // The points of the area on show moved: its panel is for the old ones.
  property bool outdated: false
  // Asked again even when what is kept is fresh: the refresh button and IPC.
  property bool forced: false
  // Like Omarchy's weather, a failed request is tried again a few times before
  // the error shows, as when the laptop wakes before the network is back.
  property int retries: 0
  property string failure: ""
  property string problem: ""
  property bool missing: false
  property bool popupOpen: false
  property real updatedAt: 0
  // A newer release, from `peakcast outdated`; empty when this one is the newest.
  property string newVersion: ""
  property int hovered: -1
  property var palette: ({})

  // The area picker: what was typed, the saved areas that match it, and the
  // places found for the last search.
  property bool picking: false
  property string typed: ""
  property var matches: []
  property var found: []
  property string searched: ""
  property bool searching: false
  property int cursor: -1
  // A saved area being dragged in the picker, as Omarchy's world clock drags its
  // cities: the row follows the pointer and the others step aside.
  property int dragFrom: -1
  property int dragTo: -1
  property real dragOffset: 0
  property real dragPitch: 0
  // The first area is the default: the panel opens on it.
  property bool fromTop: false

  readonly property int hours: panel ? panel.readings.length : 0
  // The panel kept is for another area or old points: it stays, dimmed, until the
  // new one comes, so nothing jumps.
  readonly property bool waiting: panel !== null && (String(panel.name) !== areaName || outdated)
  readonly property string areaName: areas.length > 0 ? String(areas[selected].name) : ""
  readonly property var choices: pickerChoices()

  // The roles of the Omarchy theme that the shell does not expose, as the Mac panel
  // uses them. Without the theme file, the shell's own colours.
  readonly property color textColor: Commons.Color.popups.text
  readonly property color backgroundColor: Commons.Color.popups.background
  readonly property color dimColor: paletteColor("dark_foreground", Qt.darker(textColor, 1.5))
  readonly property color gridColor: Commons.Color.muted
  readonly property color chartColor: paletteColor("dark_background", backgroundColor)
  readonly property color temperatureColor: paletteColor("bright_cyan", Commons.Color.accent)
  readonly property color windColor: paletteColor("green", textColor)
  readonly property color sunColor: paletteColor("yellow", textColor)
  readonly property color rainColor: paletteColor("blue", Commons.Color.accent)
  readonly property color snowColor: paletteColor("bright_foreground", textColor)
  readonly property color iceColor: Commons.Color.urgent
  readonly property color freezingColor: Qt.rgba(redColor.r, redColor.g, redColor.b, 0.4)
  readonly property color redColor: paletteColor("red", Commons.Color.urgent)

  // What the shell calls for `omarchy-shell shell toggle <id>`, so a key can open it.
  readonly property bool opened: popupOpen

  function open() {
    popupOpen = true
    // The theme may have changed since the last time.
    themeFile.reload()
    fromTop = true
    loadAreas()
  }

  function close() {
    picking = false
    popupOpen = false
  }

  function paletteColor(name, fallback) {
    var value = palette[name]
    return value ? value : fallback
  }

  // Lines like `green = "#9ece6a"`; anything else in the file is skipped.
  function readPalette(text) {
    var colors = {}
    var lines = String(text).split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6})"/)
      if (match) colors[match[1]] = match[2]
    }
    palette = colors
  }

  // The programs are often in ~/.local/bin, which the shell's PATH may lack. The
  // arguments go as "$@", never into the script text.
  function program(name, args) {
    return ["sh", "-c", "PATH=\"$HOME/.local/bin:$PATH\" exec \"$0\" \"$@\"", name].concat(args)
  }

  function engine(args) {
    return program("peakcast", args)
  }

  function degrees(point) {
    return point.latitude + "," + point.longitude
  }

  function checkVersion() {
    if (!versionProcess.running) versionProcess.running = true
  }

  // In Omarchy's floating terminal, as its own update runs.
  function update() {
    close()
    var script = Qt.resolvedUrl("update.sh").toString().replace("file://", "")
    Commons.Util.execArgv(["omarchy-launch-floating-terminal-with-presentation", script])
  }

  function loadAreas() {
    areasProcess.running = true
  }

  function reloadAreas(name) {
    wanted = name
    loadAreas()
  }

  function fetch() {
    if (areas.length === 0 || panelProcess.running) return
    panelProcess.command = engine(["panel", "--", areaName])
    panelProcess.running = true
  }

  function refresh() {
    checkVersion()
    forced = true
    problem = ""
    loadAreas()
  }

  function needsFetch() {
    return areas.length > 0 && (!panel || String(panel.name) !== areaName || outdated || stale())
  }

  function panelDone(code) {
    if (code === 0) {
      retries = 0
      if (needsFetch()) fetch()
    } else if (retries < 3) {
      retries++
      retryTimer.restart()
    } else {
      retries = 0
      problem = failure !== "" ? failure : "peakcast failed"
    }
  }

  // The panel starts at the hour it was made for: past that hour it is asked again.
  function stale() {
    var hour = 3600 * 1000
    return Math.floor(updatedAt / hour) !== Math.floor(Date.now() / hour)
  }

  function show(index) {
    if (index < 0 || index >= areas.length) return
    selected = index
    problem = ""
    if (needsFetch()) fetch()
  }

  function step(direction) {
    if (areas.length > 1) show((selected + direction + areas.length) % areas.length)
  }

  function readAreas(text) {
    var previous = wanted !== "" ? wanted : areaName
    wanted = ""
    try {
      var read = JSON.parse(text)
      areas = Array.isArray(read) ? read : []
    } catch (error) {
      areas = []
    }
    var index = 0
    if (!fromTop)
      for (var i = 0; i < areas.length; i++)
        if (String(areas[i].name) === previous) index = i
    fromTop = false
    selected = index
    if (picking) {
      filter(typed)
      cursor = Math.min(cursor, choices.length - 1)
    }
    if (areas.length > 0 && (forced || needsFetch())) fetch()
    forced = false
  }

  function readPanel(text) {
    try {
      panel = JSON.parse(text)
      problem = ""
      outdated = false
      updatedAt = Date.now()
    } catch (error) {
      problem = "cannot read the answer of peakcast"
    }
  }

  function toneColor(tone, tint) {
    if (tone === "snow") return snowColor
    if (tone === "ice") return iceColor
    return tint
  }

  function openPicker() {
    cursor = -1
    filter("")
    picking = true
  }

  function closePicker() {
    picking = false
  }

  // Saved areas whose name contains what was typed, ignoring case.
  function filter(text) {
    typed = text
    var needle = text.trim().toLowerCase()
    var indexes = []
    for (var i = 0; i < areas.length; i++)
      if (String(areas[i].name).toLowerCase().indexOf(needle) !== -1) indexes.push(i)
    matches = indexes
    found = []
    searched = ""
  }

  // "peak · 2502 m · Schwende-Rüte, Switzerland": what it is tells apart places with
  // the same name. The description starts with the name, which the row already shows.
  function placeDetail(place) {
    var description = String(place.description)
    var comma = description.indexOf(", ")
    var region = comma === -1 ? description : description.slice(comma + 2)
    var kind = String(place.kind).replace(/_/g, " ")
    if (place.elevation === null || place.elevation === undefined) return kind + " · " + region
    return kind + " · " + Math.round(place.elevation) + " m · " + region
  }

  function pickerChoices() {
    // The last area stays, so it shows no ×.
    var removable = areas.length > 1
    var rows = []
    // Right after the areas are read again, matches may still point past them.
    for (var i = 0; i < matches.length; i++)
      if (matches[i] < areas.length)
        rows.push({ title: String(areas[matches[i]].name), detail: "", editable: true, removable: removable })
    for (var j = 0; j < found.length; j++)
      rows.push({ title: String(found[j].name), detail: placeDetail(found[j]), editable: false, removable: false })
    return rows
  }

  function search(text) {
    if (searching || text.trim() === "") return
    searching = true
    searched = text
    searchProcess.command = engine(["search", "--json", "--", text])
    searchProcess.running = true
  }

  function readSearch(text) {
    searching = false
    try {
      var places = JSON.parse(text).places
      found = Array.isArray(places) ? places.slice(0, 10) : []
      problem = ""
    } catch (error) {
      problem = "cannot read the answer of peakcast"
    }
  }

  function pick(index) {
    closePicker()
    if (index < matches.length) {
      show(matches[index])
      return
    }
    var number = index - matches.length
    var place = found[number]
    if (!place) return
    for (var i = 0; i < areas.length; i++) {
      if (String(areas[i].name).toLowerCase() === String(place.name).toLowerCase()) {
        show(i)
        return
      }
    }
    // The search is cached, so this does not ask Nominatim again.
    run(["add", "--result", String(number + 1), "--", searched], String(place.name))
  }

  function remove(index) {
    if (index >= matches.length || matches[index] >= areas.length) return
    run(["remove", "--", String(areas[matches[index]].name)], "")
  }

  // Only the saved areas move, and only while nothing is typed: a filtered list
  // does not show their real order.
  function canDrag(index) {
    return typed.trim() === "" && index < matches.length && matches.length > 1
  }

  function beginDrag(index, pitch) {
    dropAnimation.stop()
    dragFrom = index
    dragTo = index
    dragPitch = pitch
  }

  // A row is passed once the pointer is 0.6 of a row past it, as in the world clock,
  // so the target does not flicker at the edge between two rows.
  function moveDrag(offset) {
    dragOffset = offset
    var raw = offset / dragPitch
    var held = dragTo - dragFrom
    var next = Math.abs(raw - held) >= 0.6 ? Math.round(raw) : held
    dragTo = Math.max(0, Math.min(matches.length - 1, dragFrom + next))
  }

  // The row glides into its place, then the order is saved.
  function releaseDrag() {
    dropAnimation.to = (dragTo - dragFrom) * dragPitch
    dropAnimation.restart()
  }

  function rowShift(index) {
    if (dragFrom < 0) return 0
    if (index === dragFrom) return dragOffset
    if (dragFrom < dragTo && index > dragFrom && index <= dragTo) return -dragPitch
    if (dragFrom > dragTo && index >= dragTo && index < dragFrom) return dragPitch
    return 0
  }

  // The list takes the new order at once, so nothing jumps back while the engine
  // saves it.
  function commitDrag() {
    var from = dragFrom
    var to = dragTo
    dragFrom = -1
    dragTo = -1
    dragOffset = 0
    moveArea(from, to)
  }

  // The cursor goes with the area, so Ctrl+arrows can carry it several places.
  function moveArea(from, to) {
    if (from < 0 || to < 0 || from === to || to >= matches.length) return
    var shown = areaName
    var moving = String(areas[matches[from]].name)
    var reordered = areas.slice()
    var area = reordered.splice(matches[from], 1)[0]
    reordered.splice(matches[to], 0, area)
    areas = reordered
    for (var i = 0; i < areas.length; i++)
      if (String(areas[i].name) === shown) selected = i
    filter(typed)
    cursor = to
    run(["order", "--", moving, String(to + 1)], shown)
  }

  // The keys of Omarchy's lists: the arrows wrap round, Ctrl+arrows reorder and
  // Delete removes, all on the row under the cursor.
  function pickerKey(event, text) {
    var last = choices.length - 1
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (event.key === Qt.Key_Escape) closePicker()
    else if (ctrl && event.key === Qt.Key_Up && canDrag(cursor)) moveArea(cursor, cursor - 1)
    else if (ctrl && event.key === Qt.Key_Down && canDrag(cursor)) moveArea(cursor, cursor + 1)
    else if (event.key === Qt.Key_Up) cursor = cursor <= -1 ? last : cursor - 1
    else if (event.key === Qt.Key_Down) cursor = cursor >= last ? -1 : cursor + 1
    else if (event.key === Qt.Key_Delete && cursor >= 0 && cursor < choices.length && choices[cursor].removable) remove(cursor)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (cursor >= 0) pick(cursor)
      else search(text)
    } else return false
    return true
  }

  // add, remove and order: after them the areas are read again.
  function run(args, name) {
    if (actionProcess.running) return
    actionProcess.after = name
    actionProcess.command = engine(args)
    actionProcess.running = true
  }

  // The map starts where the area on show is, and saves a new area.
  function openMap() {
    if (areas.length === 0) return
    startMap([degrees(areas[selected].summit)], "")
  }

  // The map with the marks of an area, to move them or rename it.
  function edit(index) {
    if (index >= matches.length) return
    var area = areas[matches[index]]
    if (!area) return
    var args = ["--edit", String(area.name), degrees(area.summit)]
    if (area.base) args.push(degrees(area.base))
    startMap(args, String(area.name))
  }

  // The map is a window of its own: the panel closes while it is open.
  function startMap(args, editing) {
    if (mapProcess.running) return
    close()
    mapProcess.editing = editing
    mapProcess.command = program("peakcast-map", args)
    mapProcess.running = true
  }

  // The map prints the name of the area it saved, or nothing when cancelled.
  function mapClosed(text) {
    var name = text.trim()
    if (name === "") return
    // The points moved: the forecast kept is for the old ones.
    if (mapProcess.editing === areaName) outdated = true
    reloadAreas(name)
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  NumberAnimation {
    id: dropAnimation
    target: root
    property: "dragOffset"
    duration: Style.duration(150)
    easing.type: Easing.OutCubic
    onFinished: root.commitDrag()
  }

  FileView {
    id: themeFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: root.readPalette(text())
  }

  Process {
    id: areasProcess
    command: root.engine(["areas", "--json"])
    stdout: StdioCollector { onStreamFinished: root.readAreas(text) }
    // 127: the shell did not find peakcast.
    onExited: function(code) { root.missing = code === 127 }
  }

  Process {
    id: panelProcess
    stdout: StdioCollector { onStreamFinished: if (text !== "") root.readPanel(text) }
    stderr: StdioCollector { onStreamFinished: root.failure = text.trim() }
    // Later, so that what it printed has been read first.
    onExited: function(code) { Qt.callLater(root.panelDone, code) }
  }

  Timer {
    id: retryTimer
    interval: 2500
    onTriggered: root.fetch()
  }

  // `omarchy-shell io.github.alrubearb-sys.peakcast refresh`, as Omarchy's weather
  // has, on every monitor's copy of the widget.
  ShellIpc {
    target: root.moduleName
    function refresh(): void { root.broadcast("refresh") }
  }

  // Every 6 hours, as Omarchy looks for its own updates. Without network the
  // output is empty, and the link stays hidden.
  Process {
    id: versionProcess
    command: root.engine(["outdated"])
    stdout: StdioCollector { onStreamFinished: root.newVersion = text.trim() }
  }

  Timer {
    interval: 21600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.checkVersion()
  }

  Process {
    id: searchProcess
    stdout: StdioCollector { onStreamFinished: if (text !== "") root.readSearch(text) }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") {
        root.searching = false
        root.problem = text.trim()
      }
    }
  }

  Process {
    id: actionProcess
    property string after: ""
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") root.problem = text.trim() }
    onExited: function(code) { if (code === 0) root.reloadAreas(after) }
  }

  Process {
    id: mapProcess
    property string editing: ""
    stdout: StdioCollector { onStreamFinished: root.mapClosed(text) }
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") root.problem = text.trim() }
  }

  // The icon of the Mac app (bar/ui/mountain-white.svg), in the colour of the bar.
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.popupOpen ? "" : strings.t("tooltip")
    iconComponent: Component {
      Item {
        Shape {
          readonly property real side: button.iconSize
          x: (parent.width - side) / 2
          y: (parent.height - side) / 2
          width: 36
          height: 36
          preferredRendererType: Shape.CurveRenderer
          transform: Scale { xScale: button.iconSize / 36; yScale: button.iconSize / 36 }
          ShapePath {
            fillColor: "transparent"
            strokeColor: button.foreground
            strokeWidth: 2
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M18 5 L33 31 L3 31 Z" }
          }
          ShapePath {
            fillColor: button.foreground
            strokeColor: "transparent"
            PathSvg { path: "M18 5 L25.8 18.5 L23 16 L20.5 20.5 L18 16 L15.5 20.5 L13 16 L10.2 18.5 Z" }
          }
        }
      }
    }
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) {
        root.loadAreas()
        return
      }
      if (root.popupOpen) root.close()
      else root.open()
    }
  }

  // Text from the engine is shown as plain text, never as markup.
  component Label: Text {
    textFormat: Text.PlainText
    color: root.dimColor
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  component Value: Label {
    color: root.textColor
    font.pixelSize: Style.font.title
  }

  component Cell: Label {
    color: root.textColor
    font.pixelSize: Style.font.body
  }

  component Separator: Rectangle {
    width: parent.width
    height: 1
    color: root.gridColor
  }

  // A small label above its value, as in the summit and base rows.
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

  // A line drawing in its own small box, as the Mac panel draws its controls.
  component Drawing: Shape {
    property alias path: svg.path
    property alias stroke: shapePath.strokeColor
    property alias strokeWidth: shapePath.strokeWidth
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      id: shapePath
      fillColor: "transparent"
      strokeColor: root.textColor
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { id: svg }
    }
  }

  // One SVG path of the engine, drawn in its box and stretched to the chart.
  component Trace: Shape {
    property alias path: svg.path
    property alias fill: shapePath.fillColor
    property alias stroke: shapePath.strokeColor
    property alias strokeWidth: shapePath.strokeWidth
    visible: svg.path !== ""
    width: root.panel ? root.panel.chart_width : 1
    height: root.panel ? root.panel.chart_height : 1
    preferredRendererType: Shape.CurveRenderer
    transform: Scale {
      xScale: root.panel ? parent.width / root.panel.chart_width : 1
      yScale: root.panel ? parent.height / root.panel.chart_height : 1
    }
    ShapePath {
      id: shapePath
      fillColor: "transparent"
      strokeColor: "transparent"
      strokeWidth: 0
      PathSvg { id: svg }
    }
  }

  component Plot: Item {
    id: plot
    property var chart
    property color tint
    width: parent.width
    height: Style.space(94)

    Row {
      spacing: Style.space(10)
      Repeater {
        model: plot.chart ? plot.chart.legend : []
        Label { text: modelData.text; color: root.toneColor(modelData.tone, plot.tint) }
      }
    }

    Repeater {
      model: plot.chart ? plot.chart.ticks : []
      Label {
        x: 0
        y: area.y + area.height * modelData.position - height / 2
        width: root.axis - Style.space(6)
        horizontalAlignment: Text.AlignRight
        text: modelData.text
        color: plot.chart.zero !== null && plot.chart.zero !== undefined && modelData.text === "0" ? root.textColor : root.dimColor
      }
    }

    Rectangle {
      id: area
      x: root.axis
      y: Style.space(20)
      width: parent.width - root.axis
      height: parent.height - Style.space(26)
      color: root.chartColor

      Repeater {
        model: plot.chart ? plot.chart.ticks : []
        Rectangle { y: area.height * modelData.position; width: area.width; height: 1; color: root.gridColor }
      }
      // Freezing, a thin red line so the side of 0 °C shows at a glance.
      Rectangle {
        visible: !!plot.chart && plot.chart.zero !== null && plot.chart.zero !== undefined
        y: plot.chart && plot.chart.zero !== null && plot.chart.zero !== undefined ? area.height * plot.chart.zero : 0
        width: area.width
        height: 1
        color: root.freezingColor
      }
      Repeater {
        model: root.panel ? root.panel.marks : []
        Rectangle {
          x: area.width * modelData.position
          width: 1
          height: area.height
          color: modelData.midnight ? root.dimColor : root.gridColor
        }
      }
      Trace { path: plot.chart ? plot.chart.rain : ""; fill: root.rainColor }
      Trace { path: plot.chart ? plot.chart.snow : ""; fill: root.snowColor }
      Trace { path: plot.chart ? plot.chart.ice : ""; fill: root.iceColor }
      Trace { path: plot.chart ? plot.chart.line : ""; stroke: plot.tint; strokeWidth: 2 }
      Rectangle {
        visible: root.hovered >= 0
        x: area.width * (root.hovered + 0.5) / Math.max(1, root.hours)
        width: 1
        height: area.height
        color: root.textColor
      }
    }
  }

  KeyboardPanel {
    id: card
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
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
        if (event.key === Qt.Key_Escape) root.close()
        else if (event.key === Qt.Key_Left) root.step(-1)
        else if (event.key === Qt.Key_Right) root.step(1)
        else return
        event.accepted = true
      }

      Connections {
        target: root
        function onPickingChanged() {
          if (root.picking) {
            field.text = ""
            Qt.callLater(field.forceActiveFocus)
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
          visible: root.missing
          width: parent.width
          wrapMode: Text.WordWrap
          color: root.textColor
          text: strings.t("missing") + "\n" + strings.t("install")
        }

        Label {
          visible: !root.missing && root.areas.length === 0
          width: parent.width
          wrapMode: Text.WordWrap
          color: root.textColor
          text: strings.t("noAreas")
        }

        Row {
          id: header
          visible: root.areas.length > 0
          width: parent.width
          spacing: Style.spacing.rowGap

          // Omarchy's dropdown trigger: control chrome, the current area and a chevron.
          Control {
            id: trigger
            width: header.width - mapButton.width - daylightText.width - 2 * header.spacing
            height: Style.spacing.controlHeight
            lit: root.picking
            onClicked: root.picking ? root.closePicker() : root.openPicker()

            Label {
              x: Style.spacing.controlPaddingX
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - x - chevron.width - 2 * Style.spacing.controlGap
              elide: Text.ElideRight
              text: root.areaName
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
            onClicked: root.openMap()

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
            text: root.panel ? root.panel.daylight : ""
            color: root.sunColor
            font.pixelSize: Style.font.body
          }
        }

        Separator { }

        Label {
          visible: root.problem !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          color: root.iceColor
          font.pixelSize: Style.font.body
          text: root.problem
        }

        Label {
          visible: root.areas.length > 0 && !root.panel && root.problem === ""
          text: strings.t("loading")
        }

        Column {
          visible: root.panel !== null
          opacity: root.waiting ? 0.5 : 1
          width: parent.width
          spacing: Style.spacing.rowGap

          Repeater {
            model: root.panel ? root.panel.spots : []
            Row {
              Pair { width: Style.space(92); label: modelData.label; value: modelData.height }
              Pair { width: Style.space(124); label: strings.t("sky"); value: modelData.sky }
              Pair { width: Style.space(76); label: strings.t("temperature"); value: modelData.temperature; valueColor: root.temperatureColor }
              Pair { label: strings.t("wind"); value: modelData.wind; valueColor: root.windColor }
            }
          }

          Row {
            Pair { width: Style.space(92); label: strings.t("snowLine"); value: root.panel ? root.panel.snow_line : "" }
            Pair { width: Style.space(124); label: strings.t("freezingLevel"); value: root.panel ? root.panel.freezing_level : "" }
            Pair { label: strings.t("snowDepth"); value: root.panel ? root.panel.snow_depth : "" }
          }

          Separator { }

          Label {
            text: root.hovered >= 0 && root.panel ? root.panel.readings[root.hovered] : strings.t("next")
            color: root.hovered >= 0 ? root.textColor : root.dimColor
          }

          Item {
            width: parent.width
            height: Style.space(306)

            Plot { y: 0; chart: root.panel ? root.panel.temperature : null; tint: root.temperatureColor }
            Plot { y: Style.space(96); chart: root.panel ? root.panel.wind : null; tint: root.windColor }
            Plot { y: Style.space(192); chart: root.panel ? root.panel.precipitation : null; tint: root.rainColor }

            Repeater {
              model: root.panel ? root.panel.marks : []
              Label {
                x: root.axis + (parent.width - root.axis) * modelData.position - width / 2
                y: Style.space(288)
                text: modelData.text
                color: modelData.midnight ? root.textColor : root.dimColor
              }
            }

            MouseArea {
              x: root.axis
              width: parent.width - root.axis
              height: parent.height
              hoverEnabled: true
              // Setting the same hour again changes nothing, so nothing is redrawn.
              onPositionChanged: function(mouse) {
                root.hovered = Math.min(root.hours - 1, Math.max(0, Math.floor(mouse.x / width * root.hours)))
              }
              onExited: root.hovered = -1
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
              model: root.panel ? root.panel.days : []
              Row {
                Cell { width: Style.space(44); text: modelData.name }
                Cell { width: Style.space(104); text: modelData.sky; elide: Text.ElideRight }
                Cell { width: Style.space(78); text: modelData.temperature; color: root.temperatureColor }
                Cell { width: Style.space(66); text: modelData.wind; color: root.windColor }
                Cell { width: Style.space(56); text: modelData.sun; color: root.sunColor }
                Cell { width: column.width - Style.space(348); horizontalAlignment: Text.AlignRight; text: modelData.snow; color: root.snowColor }
              }
            }
          }
        }

        Item {
          visible: root.updatedAt > 0
          width: parent.width
          height: refresh.implicitHeight

          Label {
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("updated").arg(new Date(root.updatedAt).toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), "hh:mm"))
          }
          Button {
            id: refresh
            anchors.right: parent.right
            bordered: true
            text: strings.t("refresh")
            onClicked: root.refresh()
          }
        }

        // The source of the data and, when there is one, the update link: one faint
        // line at the very end, there when wanted and never in the way.
        Item {
          visible: root.panel !== null || root.newVersion !== ""
          width: parent.width
          height: credits.implicitHeight

          Label {
            id: credits
            text: root.panel ? root.panel.credits : ""
            font.pixelSize: Style.font.caption
            opacity: 0.4
          }
          Label {
            visible: root.newVersion !== ""
            anchors.right: parent.right
            text: strings.t("update").arg(root.newVersion)
            font.pixelSize: Style.font.caption
            opacity: updateArea.containsMouse ? 0.9 : 0.4

            MouseArea {
              id: updateArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.update()
            }
          }
        }
      }

      // Above everything else; a click outside the list closes it.
      MouseArea {
        visible: root.picking
        anchors.fill: parent
        onClicked: root.closePicker()
      }

      // The list of the picker, under its trigger, as the Mac panel opens it.
      Rectangle {
        id: list
        visible: root.picking
        x: header.x + trigger.x
        y: header.y + trigger.height + Style.spacing.labelGap
        width: trigger.width
        height: rows.implicitHeight + 2 * border.width
        color: root.backgroundColor
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
              color: root.textColor
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              selectionColor: Style.selectionFill
              clip: true
              onTextEdited: {
                root.cursor = -1
                root.filter(text)
              }
              Keys.onPressed: function(event) { event.accepted = root.pickerKey(event, text) }
            }
          }

          Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.10) }

          Repeater {
            model: root.choices
            Rectangle {
              id: row
              required property var modelData
              required property int index
              width: rows.width
              height: modelData.detail === "" ? Style.spacing.popupRowHeight : Style.spacing.popupRowHeight + Style.spacing.rowPaddingX
              readonly property bool dragged: index === root.dragFrom
              z: dragged ? 2 : 0
              opacity: dragged ? 0.9 : 1
              transform: Translate {
                y: root.rowShift(row.index)
                // The dragged row follows the pointer one-to-one; the others ease aside.
                Behavior on y {
                  enabled: !row.dragged
                  NumberAnimation { duration: Style.duration(130); easing.type: Easing.OutCubic }
                }
              }
              // The dragged row is solid, so the rows it passes do not show through it.
              color: dragged ? Qt.tint(root.backgroundColor, Style.hoverFill)
                : index === root.cursor ? Style.hoverFill
                : modelData.editable && modelData.title === root.areaName ? Style.selectedFill
                : "transparent"

              MouseArea {
                property real pressY: 0
                property bool armed: false
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: row.dragged ? Qt.ClosedHandCursor
                  : root.canDrag(row.index) ? Qt.OpenHandCursor : Qt.PointingHandCursor
                // Measured in the column, which does not move; the row slides with the drag.
                function pointerY(mouse) { return mapToItem(rows, 0, mouse.y).y }
                // The mouse and the keyboard share one cursor, as in Omarchy.
                onContainsMouseChanged: if (containsMouse && root.dragFrom < 0) root.cursor = row.index
                onPressed: function(mouse) {
                  pressY = pointerY(mouse)
                  armed = false
                }
                onPositionChanged: function(mouse) {
                  if (!pressed || !root.canDrag(row.index)) return
                  var dy = pointerY(mouse) - pressY
                  // A few pixels of slack, so a click is never a reorder.
                  if (!armed) {
                    if (Math.abs(dy) < Style.space(4)) return
                    armed = true
                    root.beginDrag(row.index, row.height)
                  }
                  root.moveDrag(dy)
                }
                onReleased: {
                  if (armed) root.releaseDrag()
                  else root.pick(row.index)
                  armed = false
                }
                onCanceled: {
                  armed = false
                  root.commitDrag()
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

              // A pencil drawn like the ×, to its left: the map with this area's marks.
              Item {
                visible: row.modelData.editable && row.index === root.cursor
                x: parent.width - Style.spacing.rowPaddingX - width - (row.modelData.removable ? Style.space(24) : 0)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(20)
                height: Style.space(20)
                Drawing {
                  anchors.centerIn: parent
                  width: 11
                  height: 11
                  strokeWidth: 1.2
                  stroke: pencil.containsMouse ? root.textColor : root.dimColor
                  path: "M 1 10 L 1.5 7.5 L 8 1 L 10 3 L 3.5 9.5 Z M 6.5 2.5 L 8.5 4.5"
                }
                MouseArea {
                  id: pencil
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.edit(row.index)
                }
              }

              // The × of Omarchy's world clock, without its circle, only on the row
              // under the cursor. The 20 px box is there to be easy to hit.
              Item {
                visible: row.modelData.removable && row.index === root.cursor
                x: parent.width - Style.spacing.rowPaddingX - width
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(20)
                height: Style.space(20)
                Label {
                  anchors.centerIn: parent
                  text: "×"
                  color: cross.containsMouse ? root.textColor : root.dimColor
                  font.pixelSize: Style.font.title
                }
                MouseArea {
                  id: cross
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.remove(row.index)
                }
              }
            }
          }

          Item {
            visible: root.searching || root.choices.length === 0
            width: parent.width
            height: Style.spacing.popupRowHeight
            Label {
              x: Style.spacing.rowPaddingX
              width: parent.width - 2 * Style.spacing.rowPaddingX
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              font.pixelSize: Style.font.body
              text: root.searching ? strings.t("searching")
                : field.text === "" ? strings.t("noAreasShort")
                : strings.t("noMatches")
            }
          }
        }
      }
    }
  }
}
