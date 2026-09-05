import QtQuick
import qs.Commons
import qs.Ui

// Watchlist pill for the bar: lead coin's price and 24h movement, with the
// full watchlist in the popup panel. Left click toggles the panel, middle
// click forces a refresh.
BarWidget {
  id: root
  moduleName: "ber.omacoins"

  // display: "icon" (default) is a single glyph that saves bar space; "full"
  // shows the lead coin's price and 24h movement in the bar.
  // Set with: omarchy bar set ber.omacoins display full
  readonly property string displayMode: String(setting("display", "icon") || "icon").toLowerCase()
  readonly property bool iconOnly: displayMode === "icon"
  // Default glyph is nf-fa-btc (U+F15A) from the nerd font the bar uses.
  readonly property string defaultIcon: ""
  readonly property string iconGlyph: String(setting("icon", defaultIcon) || defaultIcon)

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // Horizontally the pill is a text label, so the open-panel dot takes the
  // label width; vertically it collapses to a single icon-sized glyph.
  readonly property real openPanelIndicatorWidth: button.labelWidth

  // Icon mode is visible immediately (the panel reports fetch problems);
  // full mode waits for a label so the bar never shows an empty pill.
  visible: iconOnly || (panelLoader.item && panelLoader.item.label !== "")
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // A local-plugin reload (a file changed under the plugin directory) has
  // the bar rebuild this widget and hand it the settings its slot was
  // mounted with. Settings written since — `omarchy bar set`, the panel's
  // settings page — were only patched into the bar's live layout, so that
  // is the fresher copy; adopt it once the bar has finished injecting.
  // Same values on a normal start, so this changes nothing there.
  function adoptBarSettings() {
    if (!root.bar || !root.bar.layoutConfig) return
    var layout = root.bar.layoutConfig
    var regions = ["left", "center", "right"]
    for (var r = 0; r < regions.length; r++) {
      var entries = layout[regions[r]] || []
      for (var i = 0; i < entries.length; i++) {
        var e = entries[i]
        if (!e || typeof e !== "object" || String(e.id || "") !== root.moduleName) continue
        var fresh = {}
        for (var k in e) if (k !== "id") fresh[k] = e[k]
        var current = {}
        for (var c in root.settings) if (c !== "id") current[c] = root.settings[c]
        if (JSON.stringify(fresh) !== JSON.stringify(current)) root.settings = fresh
        return
      }
    }
  }

  onBarChanged: {
    injectPanel()
    Qt.callLater(adoptBarSettings)
  }
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (root.vertical || root.iconOnly) ? "" : (panelLoader.item ? panelLoader.item.label : "")
    labelVisible: !root.vertical && !root.iconOnly
    hasVisualContent: root.vertical || root.iconOnly || text !== ""
    fixedWidth: (root.iconOnly && !root.vertical) ? Style.bar.iconSlot : -1
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    horizontalMargin: root.iconOnly ? 0 : 8.75
    verticalPadding: 8.75
    // In icon mode the tooltip carries the price the pill no longer shows;
    // in full mode it is suppressed because the panel is the detail view.
    tooltipText: root.iconOnly && panelLoader.item ? panelLoader.item.label : ""

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    // Vertical bars and icon mode get a single glyph instead of the text pill.
    OpticalGlyph {
      visible: root.vertical || root.iconOnly
      anchors.fill: parent
      text: root.iconGlyph
      fontFamily: button.fontFamily
      fontSize: button.fontSize
      color: button.foreground
    }
  }
}
