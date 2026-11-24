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
  readonly property int axis: Style.space(38)

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
  readonly property int maxRetries: 3
  readonly property int retryDelay: 2500
  readonly property int hourMilliseconds: 3600 * 1000
  readonly property int versionCheckInterval: 6 * hourMilliseconds
  property string failure: ""
  property string problem: ""
  property bool missing: false
  property bool popupOpen: false
  property real updatedAt: 0
  property string newVersion: ""
  property int hovered: -1
  property var palette: ({})

  property bool picking: false
  property string typed: ""
  property var matches: []
  property var found: []
  property string searched: ""
  property bool searching: false
  property string asked: ""
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
    } else if (retries < maxRetries) {
      retries++
      retryTimer.restart()
    } else {
      retries = 0
      problem = failure !== "" ? failure : "peakcast failed"
    }
  }

  // The panel starts at the hour it was made for: past that hour it is asked again.
  function stale() {
    return Math.floor(updatedAt / hourMilliseconds) !== Math.floor(Date.now() / hourMilliseconds)
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
      problem = "cannot read the answer of peakcast"
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

  function openPicker() {
    cursor = -1
    filter("")
    picking = true
  }

  function closePicker() {
    picking = false
  }

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

  function pickerChoices() {
    // The last area stays, so it shows no ×.
    var removable = areas.length > 1
    var rows = []
    // Right after the areas are read again, matches may still point past them.
    for (var i = 0; i < matches.length; i++)
      if (matches[i] < areas.length)
        rows.push({ title: String(areas[matches[i]].name), detail: "", editable: true, removable: removable })
    for (var j = 0; j < found.length; j++)
      rows.push({ title: String(found[j].name), detail: found[j].detail ? String(found[j].detail) : "", editable: false, removable: false })
    return rows
  }

  function search(text) {
    if (searching || text.trim() === "") return
    searching = true
    searched = text
    asked = text
    searchProcess.command = engine(["search", "--json", "--", text])
    searchProcess.running = true
  }

  function readSearch(text) {
    searching = false
    // What was typed changed while it searched: these places answer another text,
    // and picking one would add the wrong place.
    if (searched !== asked) return
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

  function run(args, name) {
    if (actionProcess.running) return
    actionProcess.after = name
    actionProcess.command = engine(args)
    actionProcess.running = true
  }

  function openMap() {
    if (areas.length === 0) return
    startMap([degrees(areas[selected].summit)], "")
  }

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

  function mapClosed(text) {
    var name = text.trim()
    if (name === "") return
    // The points moved: the forecast kept is for the old ones.
    if (mapProcess.editing === areaName) outdated = true
    reloadAreas(name)
  }

  moduleName: "io.github.alrubearb-sys.peakcast"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations { id: translations; directory: Qt.resolvedUrl("i18n") }

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
    interval: root.retryDelay
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
    interval: root.versionCheckInterval
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

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.popupOpen ? "" : translations.t("tooltip")
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

  ForecastPanel {
    widget: root
    strings: translations
  }
}
