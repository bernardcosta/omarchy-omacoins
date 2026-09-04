import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Coins popup: a watchlist tab (prices and 24h movement) and, when a
// portfolio file exists, a portfolio tab (what your holdings are worth),
// both from CoinGecko's keyless /coins/markets endpoint.
// Settings (shell.json entry for ber.omacoins):
//   coins:          comma-separated CoinGecko ids ("bitcoin,solana");
//                   empty means top N by market cap
//   count:          how many coins to show (default 5)
//   currency:       CoinGecko vs_currency (default usd)
//   refreshMinutes: auto-refresh interval (default 3)
//   portfolio:      holdings file (default ~/.config/omacoins/portfolio.json)
//   tab:            tab shown at startup, "watchlist" (default) or "portfolio"
//   range:          chart range at startup: "7d" (default), "30d" or "1y"
Panel {
  id: root
  moduleName: "ber.omacoins"
  ipcTarget: "ber.omacoins"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel, so everything the bar identifies a panel by must be that
  // widget.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.refreshIfStale()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refreshIfStale()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- Settings
  readonly property string customCoins: String(setting("coins", "")).trim()
  readonly property string currency: Model.normalizedCurrency(setting("currency", "usd"))
  readonly property string currencySymbol: Model.currencySymbol(currency)
  readonly property int coinCount: Math.max(1, Math.min(25, parseInt(setting("count", 5), 10) || 5))
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 3), 10) || 3)
  readonly property string home: Quickshell.env("HOME")
  readonly property string defaultPortfolioPath: home + "/.config/omacoins/portfolio.json"
  readonly property string portfolioPath: {
    var p = String(setting("portfolio", "") || "").trim()
    if (p === "") return defaultPortfolioPath
    if (p === "~") return home
    if (p.indexOf("~/") === 0) return home + p.substring(1)
    return p
  }
  readonly property string portfolioPathShort: portfolioPath.indexOf(home + "/") === 0 ? "~" + portfolioPath.substring(home.length) : portfolioPath
  readonly property string initialTab: String(setting("tab", "watchlist") || "").toLowerCase() === "portfolio" ? "portfolio" : "watchlist"
  readonly property string initialRange: Model.normalizedRange(setting("range", "7d"))

  // ---- Feeds. One request each per refresh, regardless of coin count.
  MarketsFeed { id: markets }
  MarketsFeed { id: portfolioFeed }
  // History for the 1M/1Y ranges (DefiLlama, CoinGecko as fallback), on
  // demand and cached.
  HistoryFeed { id: history }

  readonly property var rows: markets.rows

  // Currency symbol each feed's rows were priced in. Everything on screen
  // renders from these, not from the live setting: a currency change must
  // not relabel yesterday's USD numbers as euros, and the pill and the
  // panel must flip together.
  readonly property string displaySymbol: markets.rowsSymbol !== "" ? markets.rowsSymbol : currencySymbol
  readonly property string portfolioSymbol: portfolioFeed.rowsSymbol !== "" ? portfolioFeed.rowsSymbol : currencySymbol

  // Bar pill text. A binding rather than an assignment on each response, so
  // the pill tracks the rows the same way the panel rows do.
  readonly property string label: Model.barLabel(rows, displaySymbol)

  // ---- Holdings. The file is the whole portfolio: {"bitcoin": 0.5, ...}.
  //      It never leaves the machine; only the ids go to CoinGecko.
  property bool portfolioFileFound: false
  property string holdingsText: ""
  readonly property var holdings: Model.parseHoldings(holdingsText)
  readonly property string holdingIds: Model.holdingIds(holdings)
  readonly property var portfolio: Model.buildPortfolio(holdings, portfolioFeed.rows)
  // The tab appears once the file exists, even if it holds nothing yet, so
  // a half-written file gets a message instead of silence.
  readonly property bool portfolioAvailable: portfolioFileFound

  // ---- Tabs
  property string activeTab: initialTab
  onInitialTabChanged: activeTab = initialTab
  readonly property bool portfolioView: portfolioAvailable && activeTab === "portfolio"
  readonly property var activeFeed: portfolioView ? portfolioFeed : markets

  function showTab(name) {
    if (name === "portfolio" && !portfolioAvailable) return
    activeTab = name
  }

  // True between a currency change and the first response priced in it. The
  // keyless endpoint's rate limit can stretch that to a retry cycle, so the
  // footer says so instead of looking frozen.
  readonly property bool currencyPending: activeFeed.rowsSymbol !== "" && activeFeed.rowsSymbol !== currencySymbol

  // Featured coin in the watchlist hero; clicking a row or pressing Up/Down
  // changes it.
  property int selectedIndex: 0
  readonly property var selectedCoin: rows.length > 0 ? rows[Math.min(selectedIndex, rows.length - 1)] : null

  // The hero block and the row list draw whichever tab is active from the
  // same fields; Model.js shapes a coin or the portfolio into them.
  readonly property var hero: portfolioView ? Model.portfolioHero(portfolio, portfolioSymbol, chartSeries, rangeLabel) : Model.coinHero(selectedCoin, displaySymbol, chartSeries)
  readonly property var listRows: portfolioView ? Model.portfolioRows(portfolio, portfolioSymbol) : Model.watchlistRows(rows, displaySymbol)
  readonly property string listTitle: {
    if (portfolioView) return portfolio.items.length + (portfolio.items.length === 1 ? " HOLDING" : " HOLDINGS")
    return customCoins !== "" ? "WATCHLIST" : ("TOP " + coinCount + " BY MARKET CAP")
  }

  // ---- Chart range. 7d comes with the market rows; 1M and 1Y are fetched
  //      when selected — the featured coin on the watchlist, every priced
  //      holding on the portfolio — and cached as long as the data's own
  //      resolution makes worthwhile (four-hourly points for the month,
  //      daily for the year). While the panel is open, the rest of the
  //      coins on screen are prefetched behind them, so featuring another
  //      coin or switching tabs doesn't wait on a request. History is USD
  //      and scaled onto each coin's live price, so it follows the
  //      currency setting without refetching.
  property string range: initialRange
  onInitialRangeChanged: range = initialRange
  readonly property int rangeDays: Model.RANGES[range].days
  readonly property string rangeLabel: Model.RANGES[range].label
  readonly property int historyMaxAge: range === "1y" ? 12 * 60 * 60 * 1000 : 60 * 60 * 1000

  readonly property var chartIds: {
    if (portfolioView) {
      var ids = []
      for (var i = 0; i < portfolio.items.length; i++) if (portfolio.items[i].coin) ids.push(portfolio.items[i].id)
      return ids
    }
    return selectedCoin ? [selectedCoin.id] : []
  }
  readonly property string chartKey: range + "|" + chartIds.join(",")
  onChartKeyChanged: Qt.callLater(ensureHistory)

  // Everything else on screen that the chart could switch to next.
  readonly property var prefetchIds: {
    var ids = []
    var seen = {}
    for (var i = 0; i < chartIds.length; i++) seen[chartIds[i]] = true
    for (var r = 0; r < rows.length; r++) {
      if (!seen[rows[r].id]) { seen[rows[r].id] = true; ids.push(rows[r].id) }
    }
    for (var h = 0; h < portfolio.items.length; h++) {
      var it = portfolio.items[h]
      if (it.coin && !seen[it.id]) { seen[it.id] = true; ids.push(it.id) }
    }
    return ids
  }
  readonly property string prefetchKey: chartKey + "|" + prefetchIds.join(",") + "|" + opened
  onPrefetchKeyChanged: Qt.callLater(ensureHistory)

  function ensureHistory() {
    if (range === "7d") return
    history.keepOnly(rangeDays)
    if (chartIds.length > 0) history.want(chartIds, rangeDays, historyMaxAge, true)
    // Prefetch only while open: with the panel closed for hours, keeping
    // every coin's history warm would be requests for nobody.
    if (opened && prefetchIds.length > 0) history.want(prefetchIds, rangeDays, historyMaxAge, false)
  }

  function showRange(name) {
    range = Model.normalizedRange(name)
  }

  readonly property var chartSeries: {
    if (range === "7d") return portfolioView ? portfolio.sparkline : (selectedCoin ? selectedCoin.sparkline : [])
    var cache = history.cache
    if (!portfolioView) return selectedCoin ? Model.scaleSeries(history.series(selectedCoin.id, rangeDays), selectedCoin.price) : []
    var parts = []
    for (var i = 0; i < portfolio.items.length; i++) {
      var it = portfolio.items[i]
      if (!it.coin) continue
      var s = history.series(it.id, rangeDays)
      // Partial sums would misstate the total; wait for every coin.
      if (s.length < 2) return []
      parts.push({ series: Model.scaleSeries(s, it.coin.price), amount: it.amount })
    }
    return Model.sumSeries(parts)
  }
  readonly property bool chartFailed: {
    if (range === "7d" || chartSeries.length > 1) return false
    var failedAt = history.failedAt
    for (var i = 0; i < chartIds.length; i++) if (history.failed(chartIds[i], rangeDays)) return true
    return false
  }
  readonly property bool chartLoading: range !== "7d" && chartSeries.length < 2 && !chartFailed
  readonly property var chartChange: Model.rangeChange(chartSeries, portfolioView ? portfolio.total : (selectedCoin ? selectedCoin.price : null))

  // What to say when there is no hero to show.
  readonly property string statusText: {
    if (portfolioView) {
      if (holdings.length === 0)
        return holdingsText.trim() !== ""
          ? "No holdings read from " + portfolioPathShort + " — expected {\"bitcoin\": 0.5, …}"
          : "Empty portfolio — add {\"bitcoin\": 0.5, …} to " + portfolioPathShort
      if (portfolio.priced === 0 && portfolioFeed.updatedAt)
        return "None of these ids are on CoinGecko — check " + portfolioPathShort
    }
    return activeFeed.failed ? "CoinGecko unreachable (rate limit?) — retrying at next refresh" : "Fetching prices…"
  }

  // Movement colors come from the active theme's palette: every Omarchy theme
  // defines its own red and green in colors.toml, so up/down shades follow the
  // theme instead of a fixed pair. The hardcoded values remain as fallbacks
  // for a theme that lacks those keys.
  readonly property color fallbackUpColor: "#7fbf7f"
  readonly property color fallbackDownColor: "#e07a7a"
  property color upColor: fallbackUpColor
  property color downColor: fallbackDownColor

  function loadThemeColors(raw) {
    var up = fallbackUpColor
    var down = fallbackDownColor
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*(green|red)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!m) continue
      if (m[1] === "green") up = m[2]
      else down = m[2]
    }
    upColor = up
    downColor = down
  }

  // A settings edit should refetch immediately, not wait out the refresh
  // timer — but only the feed it affects.
  onCustomCoinsChanged: Qt.callLater(refreshMarkets)
  onCoinCountChanged: Qt.callLater(refreshMarkets)
  onCurrencyChanged: Qt.callLater(refresh)
  // Amount edits recompute locally; only a change in *which* coins needs
  // CoinGecko again.
  onHoldingIdsChanged: Qt.callLater(refreshPortfolio)

  function refresh() {
    holdingsFile.reload()
    refreshMarkets()
    refreshPortfolio()
    ensureHistory()
  }

  function refreshMarkets() {
    markets.fetch(Model.marketsUrl(root.customCoins, root.coinCount, root.currency), root.currencySymbol)
  }

  function refreshPortfolio() {
    if (root.holdingIds === "") {
      portfolioFeed.clear()
      return
    }
    portfolioFeed.fetch(Model.marketsUrl(root.holdingIds, root.holdings.length, root.currency), root.currencySymbol)
  }

  // Opening the panel shouldn't burn a rate-limited API call when the data
  // is under a minute old; the refresh timer and middle-click still force it.
  // The holdings file is local, so re-reading it is always free.
  function refreshIfStale() {
    holdingsFile.reload()
    if (markets.isStale(60 * 1000)) refreshMarkets()
    if (root.holdingIds !== "" && portfolioFeed.isStale(60 * 1000)) refreshPortfolio()
  }

  function moveCursor(dx, dy) {
    if (dx !== 0) {
      showTab(dx > 0 ? "portfolio" : "watchlist")
      return
    }
    if (dy === 0 || portfolioView || rows.length === 0) return
    var current = Math.min(selectedIndex, rows.length - 1)
    selectedIndex = Math.max(0, Math.min(rows.length - 1, current + dy))
  }

  function changeColor(change) {
    if (change === null || change === undefined) return Qt.darker(root.bar.foreground, 1.5)
    return change >= 0 ? upColor : downColor
  }

  function badgeFill(change) {
    var c = changeColor(change)
    return Qt.rgba(c.r, c.g, c.b, 0.16)
  }

  // Watched for live edits; also re-read on every refresh and panel open,
  // which covers the file appearing after startup and editors that save by
  // replacing the file (which an inode watch loses track of).
  FileView {
    id: holdingsFile
    path: root.portfolioPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.portfolioFileFound = true
      root.holdingsText = text()
    }
    onLoadFailed: {
      root.portfolioFileFound = false
      root.holdingsText = ""
    }
    onFileChanged: reload()
  }

  // colors.toml sits behind the current-theme symlink, which a plain file
  // watch misses when the symlink retargets. Theme switches do push the new
  // palette into the shell's Color singleton over IPC, so its property
  // changes are the reliable "theme swapped" signal to re-read the file.
  FileView {
    id: themeColorsFile
    path: root.home + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: root.loadThemeColors(text())
    onLoadFailed: root.loadThemeColors("")
  }

  Connections {
    target: Color
    function onForegroundChanged() { themeColorsFile.reload() }
    function onBackgroundChanged() { themeColorsFile.reload() }
    function onAccentChanged() { themeColorsFile.reload() }
    function onUrgentChanged() { themeColorsFile.reload() }
  }

  // Runs with the panel closed too: in `full` display mode the bar pill
  // carries a live price.
  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    // Open straight to a tab: `omarchy-shell ber.omacoins portfolio`.
    function watchlist(): void { root.showTab("watchlist"); root.openFromHotkey() }
    function portfolio(): void { root.showTab("portfolio"); root.openFromHotkey() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(coinsColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // Left/Right (h/l) switch tabs; Up/Down (j/k) feature a watchlist coin;
      // 1/2/3 pick the chart range.
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onTextKey: function(t) {
        var i = ["1", "2", "3"].indexOf(t)
        if (i >= 0) root.showRange(Model.RANGE_KEYS[i])
      }

      Flickable {
        id: coinsScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: coinsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: coinsColumn
          width: coinsScroll.width
          spacing: Style.space(12)

          // ---- Tabs: only once there is a portfolio to switch to, so the
          //      watchlist-only panel stays exactly as it was.
          Item {
            visible: root.portfolioAvailable
            width: parent.width
            height: tabRow.height

            Row {
              id: tabRow
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              spacing: Style.space(4)

              Repeater {
                model: [
                  { key: "watchlist", label: "WATCHLIST" },
                  { key: "portfolio", label: "PORTFOLIO" }
                ]

                Rectangle {
                  required property var modelData
                  readonly property bool active: root.activeTab === modelData.key
                  width: tabText.implicitWidth + Style.space(20)
                  height: tabText.implicitHeight + Style.space(10)
                  radius: height / 2
                  color: active ? Style.selectedFillFor(root.bar.foreground, Color.accent)
                                : (tabArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent")

                  Text {
                    id: tabText
                    anchors.centerIn: parent
                    text: parent.modelData.label
                    color: parent.active ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.5)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.letterSpacing: 1
                    font.bold: parent.active
                  }

                  MouseArea {
                    id: tabArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showTab(parent.modelData.key)
                  }
                }
              }
            }
          }

          Text {
            visible: !root.hero
            x: Style.space(16)
            width: parent.width - Style.space(32)
            wrapMode: Text.WordWrap
            text: root.statusText
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.italic: true
          }

          // ---- Hero: the featured coin, or the portfolio total — identity
          //      + change badge on the left, three stat columns on the
          //      right, and the big number on its own full-width row
          //      beneath (weather-hero style).
          Item {
            id: heroRow
            visible: !!root.hero
            width: parent.width
            height: Math.max(heroIdentity.height, heroStats.height)

            // Room the identity line has before it would run under the
            // stat columns.
            readonly property real leftRoom: Math.max(0, heroStats.x - heroIdentity.x - Style.space(12))

            TextMetrics {
              id: heroNameMetrics
              font: heroName.font
              text: heroName.text
            }

            Row {
              id: heroIdentity
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                id: heroSymbol
                text: root.hero ? root.hero.title : ""
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                font.letterSpacing: 1
              }
              Text {
                id: heroName
                // The portfolio hero has no subtitle; hiding it keeps the
                // Row from spacing around an empty item.
                visible: text !== ""
                anchors.verticalCenter: heroSymbol.verticalCenter
                // advanceWidth, not width: the bounding rect comes up a
                // few px short on letter-spaced text and elides needlessly.
                width: Math.min(heroNameMetrics.advanceWidth + Style.space(4),
                                Math.max(0, heroRow.leftRoom - heroSymbol.width
                                            - heroBadge.width - Style.space(16)))
                elide: Text.ElideRight
                text: root.hero ? root.hero.subtitle : ""
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                font.letterSpacing: 1
              }

              Rectangle {
                id: heroBadge
                visible: root.hero && root.hero.change !== null
                anchors.verticalCenter: heroSymbol.verticalCenter
                width: heroBadgeText.implicitWidth + Style.space(14)
                height: heroBadgeText.implicitHeight + Style.space(6)
                radius: height / 2
                color: root.hero ? root.badgeFill(root.hero.change) : "transparent"

                Text {
                  id: heroBadgeText
                  anchors.centerIn: parent
                  text: root.hero ? Model.formatChange(root.hero.change) : ""
                  color: root.hero ? root.changeColor(root.hero.change) : "transparent"
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
            }

            Row {
              id: heroStats
              anchors.right: parent.right
              anchors.rightMargin: Style.space(20)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(20)

              Repeater {
                model: root.hero ? root.hero.stats : []

                Column {
                  required property var modelData
                  spacing: Style.space(5)
                  Text {
                    text: parent.modelData.label
                    color: Qt.darker(root.bar.foreground, 1.5)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }
                  Text {
                    text: parent.modelData.value
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.subtitle
                  }
                }
              }
            }
          }

          // ---- Big number on its own row: full width at its designed
          //      size. HorizontalFit stays as the fallback, so it only
          //      shrinks if the value outgrows the panel itself.
          Text {
            id: heroPrice
            visible: !!root.hero
            x: Style.space(16)
            width: parent.width - Style.space(32)
            text: root.hero ? root.hero.price : ""
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            // Deliberately oversized, outside the Style.font.* scale
            // (weather's hero does the same).
            font.pixelSize: 34
            font.bold: true
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 18
            elide: Text.ElideRight
          }

          // ---- Chart: the coin's price, or the portfolio total, over the
          //      selected range. Kept at full height while a range loads
          //      so the panel doesn't jump.
          Canvas {
            id: spark
            visible: !!root.hero
            width: parent.width - Style.space(32)
            height: Style.space(44)
            anchors.horizontalCenter: parent.horizontalCenter

            readonly property var series: root.hero ? root.hero.sparkline : []
            readonly property color lineColor: series.length > 1 && series[series.length - 1] >= series[0] ? root.upColor : root.downColor

            onSeriesChanged: requestPaint()
            onLineColorChanged: requestPaint()

            Text {
              anchors.centerIn: parent
              visible: root.chartLoading || root.chartFailed
              text: root.chartFailed ? "History unavailable (rate limit?)" : "Loading " + root.rangeDays + " days…"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.italic: true
            }

            onPaint: {
              var ctx = getContext("2d")
              ctx.clearRect(0, 0, width, height)
              var s = series
              if (!s || s.length < 2) return

              var min = Math.min.apply(null, s)
              var max = Math.max.apply(null, s)
              var span = (max - min) || 1
              var pad = 2
              var h = height - pad * 2
              var stepX = width / (s.length - 1)

              ctx.beginPath()
              for (var i = 0; i < s.length; i++) {
                var x = i * stepX
                var y = pad + h - ((s[i] - min) / span) * h
                if (i === 0) ctx.moveTo(x, y)
                else ctx.lineTo(x, y)
              }
              ctx.strokeStyle = lineColor
              ctx.lineWidth = 2
              ctx.lineJoin = "round"
              ctx.stroke()

              // Soft fill fading to transparent under the line.
              ctx.lineTo(width, height)
              ctx.lineTo(0, height)
              ctx.closePath()
              var grad = ctx.createLinearGradient(0, 0, 0, height)
              grad.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.18))
              grad.addColorStop(1, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0))
              ctx.fillStyle = grad
              ctx.fill()
            }
          }

          // ---- Range picker under the chart, with the move over that
          //      range on the right. Shared by both tabs.
          Item {
            visible: !!root.hero
            width: parent.width
            height: rangeRow.height

            Row {
              id: rangeRow
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              spacing: Style.space(2)

              Repeater {
                model: Model.RANGE_KEYS

                Rectangle {
                  required property string modelData
                  readonly property bool active: root.range === modelData
                  width: rangeText.implicitWidth + Style.space(14)
                  height: rangeText.implicitHeight + Style.space(8)
                  radius: height / 2
                  color: active ? Style.selectedFillFor(root.bar.foreground, Color.accent)
                                : (rangeArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent")

                  Text {
                    id: rangeText
                    anchors.centerIn: parent
                    text: Model.RANGES[parent.modelData].label
                    color: parent.active ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: parent.active
                  }

                  MouseArea {
                    id: rangeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showRange(parent.modelData)
                  }
                }
              }
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              visible: root.chartChange !== null
              text: Model.formatChange(root.chartChange)
              color: root.changeColor(root.chartChange)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          // ---- Divider between hero and the list.
          Rectangle {
            visible: root.listRows.length > 0
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
          }

          Item {
            visible: root.listRows.length > 0
            width: parent.width
            height: headerTitle.implicitHeight

            Text {
              id: headerTitle
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              text: root.listTitle
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              text: "24H"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
            }
          }

          // ---- Rows: lead (rank) + symbol + detail left, value + change
          //      badge right. Watchlist rows hover and click to feature the
          //      coin above; portfolio rows are read-only.
          Column {
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.listRows

              Rectangle {
                required property var modelData
                required property int index
                readonly property bool selected: modelData.selectable && index === root.selectedIndex
                width: parent.width
                height: Style.space(32)
                radius: Style.cornerRadius
                // The featured coin keeps the hover fill, so j/k and clicks
                // both leave a visible cursor on the list.
                color: (selected || (modelData.selectable && rowArea.containsMouse)) ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

                Text {
                  id: rankText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  width: modelData.lead !== "" ? Style.space(22) : 0
                  text: modelData.lead
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                // Measured off-screen so the column can size itself to the
                // ticker without `width` binding back onto its own
                // implicitWidth.
                TextMetrics {
                  id: symbolMetrics
                  font: symbolText.font
                  text: symbolText.text
                }

                Text {
                  id: symbolText
                  anchors.left: rankText.right
                  anchors.verticalCenter: parent.verticalCenter
                  // Fixed column so names line up, but a long ticker
                  // (FIGR_HELOC) widens it up to a cap and elides past that,
                  // instead of overprinting the name next to it.
                  width: Math.max(Style.space(58),
                                  Math.min(symbolMetrics.width + Style.space(8),
                                           Style.space(112)))
                  elide: Text.ElideRight
                  text: modelData.symbol
                  color: selected ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.1)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }

                Text {
                  anchors.left: symbolText.right
                  anchors.right: priceText.left
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.detail
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  id: priceText
                  anchors.right: changeBadge.left
                  anchors.rightMargin: Style.space(14)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.value
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.subtitle
                }

                Rectangle {
                  id: changeBadge
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(58)
                  height: changeText.implicitHeight + Style.space(6)
                  radius: height / 2
                  color: root.badgeFill(modelData.change)

                  Text {
                    id: changeText
                    anchors.centerIn: parent
                    text: Model.formatChange(modelData.change) || "—"
                    color: root.changeColor(modelData.change)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }

                MouseArea {
                  id: rowArea
                  anchors.fill: parent
                  hoverEnabled: modelData.selectable
                  cursorShape: modelData.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: if (modelData.selectable) root.selectedIndex = index
                }
              }
            }
          }

          // ---- Divider + footer
          Rectangle {
            visible: root.listRows.length > 0
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
          }

          Item {
            visible: root.listRows.length > 0
            width: parent.width
            height: footerText.implicitHeight

            Text {
              id: footerText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              text: (root.range !== "7d" ? "CoinGecko · DefiLlama" : "CoinGecko")
                    + (root.currencyPending
                                    ? " · switching to " + root.currency.toUpperCase() + "…"
                                    : (root.activeFeed.updatedAt ? " · updated " + Qt.formatTime(root.activeFeed.updatedAt, "HH:mm") : ""))
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
