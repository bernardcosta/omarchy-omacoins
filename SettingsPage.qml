import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The panel's settings page: what `omarchy bar set ber.omacoins …` and a
// hand-edited portfolio.json do, as a form. Pure view — every change goes
// back through the panel (`panel.set…`, `panel.add…`), which persists it
// and lets the new value flow back down as a setting, so the controls
// here never hold state of their own beyond what is being typed.
//
// Two things the panel needs from this page: `editing`, so its key catcher
// steps aside while a field or dropdown owns the keyboard, and `reset()`,
// called when the page closes, so a half-typed search does not greet the
// next visit.
FocusScope {
  id: page

  property var panel: null

  readonly property color fg: panel && panel.bar ? panel.bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.5)
  readonly property string fontFamily: panel && panel.bar ? panel.bar.fontFamily : Style.font.family
  readonly property bool customWatchlist: panel ? panel.customCoins !== "" : false

  // A field or the currency dropdown has the keyboard.
  readonly property bool editing: activeFocus || currencyPicker.popupOpen

  // Coin picked from search for a new holding, waiting for its amount.
  property var pendingHolding: null

  implicitHeight: column.implicitHeight
  height: implicitHeight

  function reset() {
    watchSearch.clear()
    holdingSearch.clear()
    watchField.text = ""
    holdingField.text = ""
    amountField.text = ""
    pendingHolding = null
  }

  function unfocus() {
    if (panel) panel.releaseFocus()
  }

  function addWatchCoin(coin) {
    if (!coin || !panel) return
    panel.addWatchCoin(coin)
    watchField.text = ""
    watchSearch.clear()
  }

  function chooseHolding(coin) {
    if (!coin) return
    pendingHolding = coin
    holdingField.text = ""
    holdingSearch.clear()
    amountField.text = ""
    amountField.forceActiveFocus()
  }

  function commitPendingHolding() {
    var n = Model.parseAmount(amountField.text)
    if (n === null || !pendingHolding || !panel) return
    panel.setHolding(pendingHolding.id, n, pendingHolding)
    pendingHolding = null
    amountField.text = ""
    unfocus()
  }

  function cancelPendingHolding() {
    pendingHolding = null
    amountField.text = ""
    unfocus()
  }

  SearchFeed { id: watchSearch }
  SearchFeed { id: holdingSearch }

  // Clicking bare page (a label, the gap between rows) takes the keyboard
  // back from whichever field had it, so Esc closes the page again.
  MouseArea {
    anchors.fill: parent
    onClicked: page.unfocus()
  }

  // ---- Building blocks -------------------------------------------------

  // Label + description on the left, a control on the right.
  component SettingRow: Item {
    property string label: ""
    property string description: ""
    default property alias control: slot.data

    width: parent ? parent.width : 0
    implicitHeight: Math.max(labels.implicitHeight, slot.childrenRect.height) + Style.space(6)
    height: implicitHeight

    Column {
      id: labels
      anchors.left: parent.left
      anchors.leftMargin: Style.space(16)
      anchors.right: slot.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: label
        color: page.fg
        font.family: page.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        textFormat: Text.PlainText
        visible: description !== ""
        width: parent.width
        text: description
        color: page.dim
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    Item {
      id: slot
      anchors.right: parent.right
      anchors.rightMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      width: childrenRect.width
      height: childrenRect.height
    }
  }

  // Section title with an optional hint at the right edge.
  component SectionTitle: Item {
    id: section
    property string text: ""
    property string hint: ""

    width: parent ? parent.width : 0
    height: titleText.implicitHeight

    PanelSectionHeader {
      id: titleText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(16)
      text: section.text
      foreground: page.fg
      fontFamily: page.fontFamily
      font.letterSpacing: 1
    }
    Text {
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.rightMargin: Style.space(16)
      anchors.baseline: titleText.baseline
      visible: section.hint !== ""
      text: section.hint
      color: page.dim
      font.family: page.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }
  }

  // One coin in a list: ticker, name, and whatever the caller parks at the
  // right edge (a trash can, an amount field). Same column widths as the
  // watchlist rows on the main page, so the two read as one list.
  component CoinRow: Item {
    property string symbol: ""
    property string name: ""
    property bool priced: true
    // Shown in place of a missing name once the feed has had its say.
    property string unpricedText: ""
    default property alias trailing: trailingSlot.data

    width: parent ? parent.width : 0
    height: Style.space(32)

    TextMetrics {
      id: symbolMetrics
      font: symbolText.font
      text: symbolText.text
    }

    Text {
      id: symbolText
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(Style.space(58), Math.min(symbolMetrics.width + Style.space(8), Style.space(112)))
      elide: Text.ElideRight
      text: symbol
      color: Qt.darker(page.fg, 1.1)
      font.family: page.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      anchors.left: symbolText.right
      anchors.right: trailingSlot.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: name !== "" ? name : (priced ? "" : unpricedText)
      color: page.dim
      font.family: page.fontFamily
      font.pixelSize: Style.font.body
      font.italic: name === ""
      elide: Text.ElideRight
    }

    Item {
      id: trailingSlot
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      width: childrenRect.width
      height: childrenRect.height
    }
  }

  component RemoveButton: PanelActionButton {
    iconText: "󰩺"
    tooltipText: "Remove"
    foreground: page.fg
    hoverColor: Color.urgent
    fontFamily: page.fontFamily
  }

  // Search box for a coin. Up/Down walk the suggestions under it, Enter
  // picks, Esc clears and hands the keyboard back to the panel.
  component CoinSearchField: TextField {
    property var feed: null
    property int cursor: 0
    signal picked(var coin)

    x: Style.space(16)
    width: parent ? parent.width - Style.space(32) : implicitWidth
    foreground: page.fg
    font.family: page.fontFamily

    onTextChanged: {
      if (feed) feed.search(text)
      cursor = 0
    }

    Keys.onPressed: function(event) {
      var n = feed ? feed.results.length : 0
      if (event.key === Qt.Key_Escape) {
        text = ""
        if (feed) feed.clear()
        page.unfocus()
        event.accepted = true
      } else if (event.key === Qt.Key_Down) {
        if (n > 0) cursor = Math.min(n - 1, cursor + 1)
        event.accepted = true
      } else if (event.key === Qt.Key_Up) {
        cursor = Math.max(0, cursor - 1)
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (n > 0) picked(feed.results[Math.min(cursor, n - 1)])
        event.accepted = true
      }
    }
  }

  // Suggestions under a search field: CoinGecko's matches with their ids,
  // or one line saying why there are none.
  component Suggestions: Column {
    id: suggestions
    property var feed: null
    property var field: null
    signal picked(var coin)

    width: parent ? parent.width : 0
    spacing: 0
    visible: suggestions.field && suggestions.field.text.trim().length >= 2

    Text {
      textFormat: Text.PlainText
      visible: suggestions.feed && suggestions.feed.results.length === 0
      x: Style.space(16)
      width: parent.width - Style.space(32)
      height: Style.space(26)
      verticalAlignment: Text.AlignVCenter
      text: !suggestions.feed ? ""
        : suggestions.feed.busy ? "Searching CoinGecko…"
        : suggestions.feed.failed ? "CoinGecko is rate limiting — try again in a moment"
        : suggestions.feed.query !== "" ? "No coins match" : ""
      color: page.dim
      font.family: page.fontFamily
      font.pixelSize: Style.font.caption
      font.italic: true
      elide: Text.ElideRight
    }

    Repeater {
      model: suggestions.feed ? suggestions.feed.results : []

      Rectangle {
        required property var modelData
        required property int index
        readonly property bool current: suggestions.field && suggestions.field.cursor === index
        width: parent.width
        height: Style.space(30)
        radius: Style.cornerRadius
        color: current ? Style.hoverFillFor(page.fg, Color.accent) : "transparent"

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          anchors.right: idText.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.symbol
            color: current ? Style.hoverStateColor(page.fg, Color.accent) : page.fg
            font.family: page.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.name
            color: page.dim
            font.family: page.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            visible: modelData.rank !== null
            anchors.verticalCenter: parent.verticalCenter
            text: "#" + modelData.rank
            color: Qt.darker(page.fg, 1.8)
            font.family: page.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // The CoinGecko id is what ends up in the settings, so it is shown
        // rather than hidden behind the name.
        Text {
          id: idText
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.rightMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.id
          color: Qt.darker(page.fg, 1.6)
          font.family: page.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: if (suggestions.field) suggestions.field.cursor = parent.index
          onClicked: suggestions.picked(parent.modelData)
        }
      }
    }
  }

  // ---- The page ----------------------------------------------------------

  Column {
    id: column
    width: parent.width
    spacing: Style.space(12)

    // ---- General
    SectionTitle { text: "GENERAL" }

    Toggle {
      x: Style.space(16)
      width: parent.width - Style.space(32)
      label: "Show price in the bar"
      description: "Off keeps a single icon; on shows the lead coin's price and 24h move."
      foreground: page.fg
      fontFamily: page.fontFamily
      checked: panel ? panel.displayMode !== "icon" : false
      onClicked: if (panel) panel.setDisplay(checked ? "icon" : "full")
    }

    SettingRow {
      label: "Currency"
      description: "Prices and totals are quoted in this currency."

      SearchableDropdown {
        id: currencyPicker
        width: Style.space(190)
        showLabel: false
        options: Model.CURRENCIES
        value: panel ? panel.currency : "usd"
        placeholderText: "Search currency"
        emptyText: "No such currency"
        foreground: page.fg
        fontFamily: page.fontFamily
        onChanged: function(v) {
          if (panel) panel.setCurrency(v)
          page.unfocus()
        }
      }
    }

    SettingRow {
      visible: !page.customWatchlist
      label: "Top coins"
      description: "How many coins to list while the watchlist is empty."

      NumberField {
        from: 1
        to: 25
        value: panel ? panel.coinCount : 5
        fieldWidth: Style.space(92)
        foreground: page.fg
        fontFamily: page.fontFamily
        onModified: function(v) { if (panel) panel.setCoinCount(v) }
      }
    }

    SettingRow {
      label: "Refresh"
      description: "Minutes between price updates."

      NumberField {
        from: 1
        to: 1440
        value: panel ? panel.refreshMinutes : 3
        fieldWidth: Style.space(92)
        foreground: page.fg
        fontFamily: page.fontFamily
        onModified: function(v) { if (panel) panel.setRefreshMinutes(v) }
      }
    }

    PanelSeparator { foreground: page.fg }

    // ---- Watchlist
    SectionTitle {
      text: "WATCHLIST"
      hint: page.customWatchlist
        ? (panel.watchlistEditRows.length + (panel.watchlistEditRows.length === 1 ? " COIN" : " COINS"))
        : (panel ? "TOP " + panel.coinCount + " BY MARKET CAP" : "")
    }

    Text {
      textFormat: Text.PlainText
      visible: panel && panel.watchlistEditRows.length === 0
      x: Style.space(16)
      width: parent.width - Style.space(32)
      text: page.customWatchlist ? "No coins yet." : "Waiting for the market list…"
      color: page.dim
      font.family: page.fontFamily
      font.pixelSize: Style.font.body
      font.italic: true
    }

    Column {
      width: parent.width
      spacing: Style.space(2)

      Repeater {
        model: panel ? panel.watchlistEditRows : []

        CoinRow {
          required property var modelData
          symbol: modelData.symbol
          name: modelData.name
          priced: modelData.priced
          unpricedText: panel && panel.marketsAnswered ? "not a CoinGecko id" : ""

          RemoveButton {
            onClicked: if (panel) panel.removeWatchCoin(modelData.id)
          }
        }
      }
    }

    CoinSearchField {
      id: watchField
      feed: watchSearch
      placeholderText: "Add a coin — name or ticker"
      onPicked: function(coin) { page.addWatchCoin(coin) }
    }

    Suggestions {
      feed: watchSearch
      field: watchField
      onPicked: function(coin) { page.addWatchCoin(coin) }
    }

    Item {
      visible: page.customWatchlist
      width: parent.width
      height: resetButton.implicitHeight

      Button {
        id: resetButton
        anchors.left: parent.left
        anchors.leftMargin: Style.space(16)
        text: "Back to top " + (panel ? panel.coinCount : 5) + " by market cap"
        bordered: true
        foreground: page.fg
        fontFamily: page.fontFamily
        fontSize: Style.font.caption
        onClicked: if (panel) panel.resetWatchlist()
      }
    }

    PanelSeparator { foreground: page.fg }

    // ---- Portfolio
    SectionTitle {
      text: "PORTFOLIO"
      hint: panel ? panel.portfolioPathShort : ""
    }

    Text {
      textFormat: Text.PlainText
      visible: panel && panel.holdingEditRows.length === 0 && !page.pendingHolding
      x: Style.space(16)
      width: parent.width - Style.space(32)
      text: "No holdings yet. Add a coin and how much of it you hold; it never leaves this machine."
      color: page.dim
      font.family: page.fontFamily
      font.pixelSize: Style.font.body
      font.italic: true
      wrapMode: Text.WordWrap
    }

    Column {
      width: parent.width
      spacing: Style.space(2)

      Repeater {
        id: holdingsRepeater
        model: panel ? panel.holdingEditRows : []

        CoinRow {
          id: holdingRow
          required property var modelData
          symbol: modelData.symbol
          name: modelData.name
          priced: modelData.priced
          unpricedText: panel && panel.portfolioAnswered ? "not a CoinGecko id" : ""

          Row {
            spacing: Style.space(4)

            TextField {
              id: amountEdit
              width: Style.space(104)
              anchors.verticalCenter: parent.verticalCenter
              verticalPadding: Style.space(3)
              horizontalAlignment: TextInput.AlignRight
              text: Model.editableAmount(holdingRow.modelData.amount)
              foreground: page.fg
              font.family: page.fontFamily
              font.pixelSize: Style.font.body

              // Enter and focus loss both finish an edit; commit once.
              property string committed: ""
              Component.onCompleted: committed = text

              // The write rebuilds these rows, which would pull this field
              // out from under a handler still running — so it is deferred
              // until the handler is done.
              function commit() {
                if (text === committed) return
                var n = Model.parseAmount(text)
                if (n === null) {
                  text = Model.editableAmount(holdingRow.modelData.amount)
                  return
                }
                committed = text
                if (n === holdingRow.modelData.amount || !panel) return
                var host = panel
                var id = holdingRow.modelData.id
                Qt.callLater(function() { host.setHolding(id, n, null) })
              }

              onEditingFinished: commit()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  text = Model.editableAmount(holdingRow.modelData.amount)
                  page.unfocus()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  // Dropping focus finishes the edit, which commits.
                  page.unfocus()
                  event.accepted = true
                }
              }
            }

            RemoveButton {
              anchors.verticalCenter: parent.verticalCenter
              onClicked: if (panel) panel.removeHolding(holdingRow.modelData.id)
            }
          }
        }
      }
    }

    // A coin picked from search, waiting for its amount.
    CoinRow {
      visible: !!page.pendingHolding
      symbol: page.pendingHolding ? page.pendingHolding.symbol : ""
      name: page.pendingHolding ? page.pendingHolding.name : ""

      Row {
        spacing: Style.space(4)

        TextField {
          id: amountField
          width: Style.space(104)
          anchors.verticalCenter: parent.verticalCenter
          verticalPadding: Style.space(3)
          horizontalAlignment: TextInput.AlignRight
          placeholderText: "Amount"
          foreground: page.fg
          font.family: page.fontFamily
          font.pixelSize: Style.font.body

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              page.cancelPendingHolding()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              page.commitPendingHolding()
              event.accepted = true
            }
          }
        }

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰄬"
          tooltipText: "Add holding"
          enabled: Model.parseAmount(amountField.text) !== null
          foreground: page.fg
          hoverColor: Color.accent
          fontFamily: page.fontFamily
          onClicked: page.commitPendingHolding()
        }

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰅖"
          tooltipText: "Cancel"
          foreground: page.fg
          fontFamily: page.fontFamily
          onClicked: page.cancelPendingHolding()
        }
      }
    }

    CoinSearchField {
      id: holdingField
      feed: holdingSearch
      placeholderText: "Add a holding — name or ticker"
      onPicked: function(coin) { page.chooseHolding(coin) }
    }

    Suggestions {
      feed: holdingSearch
      field: holdingField
      onPicked: function(coin) { page.chooseHolding(coin) }
    }

    // Breathing room under the last field so it never sits on the border.
    Item { width: 1; height: Style.space(2) }
  }
}
