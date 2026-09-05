import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Coins popup: a watchlist tab (prices and 24h movement), a portfolio tab
// (what your holdings are worth), both from CoinGecko's keyless
// /coins/markets endpoint, and a settings page (the gear) that edits the
// entries below and the holdings file in place.
// Settings (shell.json entry for ber.omacoins):
//   display:        "icon" (default) or "full" — the bar pill's shape
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
    if (settingsOpen) closeSettings()
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
  // Read here as well as in BarWidget so the settings page can show it.
  readonly property string displayMode: String(setting("display", "icon") || "icon").toLowerCase()

  // The coin pages size the panel to their content and never scroll. The
  // settings page keeps a fixed height — the coin page's, or this floor if
  // that is shorter — and scrolls inside it, so opening the gear never
  // shrinks the panel.
  readonly property int settingsMinHeight: Style.space(520)

  // ---- Settings page. Writes go through the shell's own inline-entry
  //      updater (what `omarchy bar set` ends up calling), applied locally
  //      first so the control moves on the click and the shell.json write
  //      comes back as the same value. With no writable entry (the widget
  //      is not in the layout) the change lasts the session.
  property bool settingsOpen: false
  onSettingsOpenChanged: coinsScroll.contentY = 0

  function openSettings() { settingsOpen = true }

  function closeSettings() {
    settingsOpen = false
    settingsPage.reset()
    releaseFocus()
  }

  function toggleSettings() {
    if (settingsOpen) closeSettings()
    else openSettings()
  }

  // Hands the keyboard back to the panel after a field is done with it.
  function releaseFocus() { keyCatcher.forceActiveFocus() }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setDisplay(mode) { persistSettings({ display: mode === "full" ? "full" : "icon" }) }
  function setCurrency(code) { persistSettings({ currency: Model.normalizedCurrency(code) }) }
  function setCoinCount(n) { persistSettings({ count: Math.max(1, Math.min(25, parseInt(n, 10) || 5)) }) }
  function setRefreshMinutes(n) { persistSettings({ refreshMinutes: Math.max(1, parseInt(n, 10) || 3) }) }

  // Coins picked out of search this session, so a freshly added id shows
  // its name before the next price response names it.
  property var knownCoins: ({})

  function rememberCoin(coin) {
    if (!coin || !coin.id) return
    var next = {}
    for (var k in knownCoins) next[k] = knownCoins[k]
    next[coin.id] = { symbol: coin.symbol, name: coin.name }
    knownCoins = next
  }

  // What the watchlist section edits: the `coins` setting, literally. An
  // empty list is `coins ""` — the panel shows the top N — and the first
  // coin added starts a list of one, exactly as the CLI would.
  readonly property var watchlistIds: Model.coinIdList(customCoins)

  // Name and ticker for an id, from either feed's rows or this session's
  // search picks. The settings lists bind through this function per row,
  // so a price refresh renames rows in place instead of rebuilding them
  // out from under a field being typed in.
  function coinInfoFor(id) {
    return Model.coinInfo(id, [portfolioFeed.rows, rows], knownCoins)
  }
  // A feed's rows are "current" when they answer the request the settings
  // call for right now. Only then does an id missing from them mean
  // CoinGecko doesn't know it, rather than that the answer is still on
  // its way.
  readonly property bool marketsCurrent: markets.rowsUrl !== "" && markets.rowsUrl === Model.marketsUrl(customCoins, coinCount, currency)
  readonly property bool portfolioCurrent: portfolioFeed.rowsUrl !== "" && portfolioFeed.rowsUrl === Model.marketsUrl(holdingIds, holdings.length, currency)

  // Remaining settings, mirrored so the page can offer every key the CLI
  // takes. Raw strings: empty means "default", as `omarchy bar set … ""`.
  readonly property string iconSetting: String(setting("icon", "") || "")
  readonly property string portfolioSetting: String(setting("portfolio", "") || "")
  function setTab(name) { persistSettings({ tab: name === "portfolio" ? "portfolio" : "watchlist" }) }
  function setRange(name) { persistSettings({ range: Model.normalizedRange(name) }) }
  function setIcon(glyph) { persistSettings({ icon: String(glyph || "").trim() }) }
  function setPortfolioPath(path) { persistSettings({ portfolio: String(path || "").trim() }) }

  function setWatchlist(ids) { persistSettings({ coins: Model.joinCoinIds(ids) }) }
  function addWatchCoin(coin) {
    rememberCoin(coin)
    setWatchlist(Model.withCoin(watchlistIds, coin.id))
  }
  function removeWatchCoin(id) { setWatchlist(Model.withoutCoin(watchlistIds, id)) }
  function clearWatchlist() { setWatchlist([]) }

  // ---- Holdings writes. The file is rewritten whole, in the documented
  //      id → amount form; the new text is applied locally at once, so the
  //      total updates before the write lands. Writes queue behind an
  //      in-flight one rather than racing it, land atomically (temp file
  //      and rename, so the watcher never reads a half-written file), and
  //      the file is only re-read once the last of them is down.
  property string holdingsPending: ""
  readonly property bool holdingsWriting: holdingsWriter.running || holdingsPending !== ""

  function setHolding(id, amount, coin) {
    if (coin) rememberCoin(coin)
    writeHoldings(Model.holdingsWith(holdings, id, amount))
  }

  function removeHolding(id) { writeHoldings(Model.holdingsWithout(holdings, id)) }

  function writeHoldings(list) {
    var text = Model.serializeHoldings(list)
    holdingsText = text
    portfolioFileFound = true
    holdingsPending = text
    flushHoldings()
  }

  function flushHoldings() {
    if (holdingsWriter.running) return
    if (holdingsPending === "") {
      holdingsFile.reload()
      return
    }
    var text = holdingsPending
    holdingsPending = ""
    // Path and text travel as arguments, never inside the script.
    holdingsWriter.command = ["sh", "-c",
      'mkdir -p -- "$(dirname -- "$0")" && printf "%s" "$1" > "$0.tmp" && mv -f -- "$0.tmp" "$0"',
      root.portfolioPath, text]
    holdingsWriter.running = true
  }

  Process {
    id: holdingsWriter
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("omacoins: could not write " + root.portfolioPath + " (exit " + exitCode + ")")
      Qt.callLater(root.flushHoldings)
    }
  }

  // ---- Feeds. One request each per refresh, regardless of coin count.
  MarketsFeed { id: markets }
  MarketsFeed { id: portfolioFeed }
  // History for the 1M/1Y ranges (DefiLlama, CoinGecko as fallback), on
  // demand and cached.
  HistoryFeed { id: history }

  // Rows for the list, kept in step with the settings ahead of CoinGecko:
  // - top N: only a top-N answer counts (ordered by market cap), trimmed to
  //   the count, so a lower count applies at once;
  // - a named list: whichever of its ids the last answer priced, so a
  //   removed coin goes at once and one just added joins when its row
  //   lands. Anything still missing gets the "fetching" row under the
  //   list while the request is out. The bar pill keeps the raw rows so
  //   it does not blink meanwhile.
  readonly property bool rowsFromTopN: markets.rowsUrl !== "" && Model.urlIds(markets.rowsUrl) === ""
  readonly property var rows: {
    var ids = Model.coinIdList(customCoins)
    if (ids.length === 0) return rowsFromTopN ? markets.rows.slice(0, coinCount) : []
    var out = []
    for (var i = 0; i < markets.rows.length; i++) if (ids.indexOf(markets.rows[i].id) >= 0) out.push(markets.rows[i])
    return out
  }
  readonly property int rowsExpected: customCoins === "" ? coinCount : Model.coinIdList(customCoins).length
  readonly property int rowsMissing: Math.max(0, rowsExpected - rows.length)
  // Rows still to come: fewer than asked for, and the current request has
  // not answered yet. Once it has, a missing id is simply one CoinGecko
  // doesn't know.
  readonly property bool rowsPending: rowsMissing > 0 && !marketsCurrent

  // Currency symbol each feed's rows were priced in. Everything on screen
  // renders from these, not from the live setting: a currency change must
  // not relabel yesterday's USD numbers as euros, and the pill and the
  // panel must flip together.
  readonly property string displaySymbol: markets.rowsSymbol !== "" ? markets.rowsSymbol : currencySymbol
  readonly property string portfolioSymbol: portfolioFeed.rowsSymbol !== "" ? portfolioFeed.rowsSymbol : currencySymbol

  // Bar pill text. A binding rather than an assignment on each response, so
  // the pill tracks the rows the same way the panel rows do.
  readonly property string label: Model.barLabel(markets.rows, displaySymbol)

  // ---- Holdings. The file is the whole portfolio: {"bitcoin": 0.5, ...}.
  //      It never leaves the machine; only the ids go to CoinGecko.
  property bool portfolioFileFound: false
  property string holdingsText: ""
  readonly property var holdings: Model.parseHoldings(holdingsText)
  readonly property string holdingIds: Model.holdingIds(holdings)
  readonly property var portfolio: Model.buildPortfolio(holdings, portfolioFeed.rows)
  readonly property bool portfolioAvailable: portfolioFileFound

  // ---- Tabs. Both are always there: the portfolio tab is where holdings
  //      get added from, so it cannot wait for the file to exist.
  property string activeTab: initialTab
  onInitialTabChanged: activeTab = initialTab
  readonly property bool portfolioView: activeTab === "portfolio"
  readonly property var activeFeed: portfolioView ? portfolioFeed : markets

  function showTab(name) {
    activeTab = name === "portfolio" ? "portfolio" : "watchlist"
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
    var failedAt = history.failedAt  // read only to re-evaluate when a fetch fails
    for (var i = 0; i < chartIds.length; i++) if (history.failed(chartIds[i], rangeDays)) return true
    return false
  }
  readonly property bool chartLoading: range !== "7d" && chartSeries.length < 2 && !chartFailed
  readonly property var chartChange: Model.rangeChange(chartSeries, portfolioView ? portfolio.total : (selectedCoin ? selectedCoin.price : null))

  // What to say when there is no hero to show.
  readonly property string statusText: {
    if (portfolioView) {
      if (holdings.length === 0)
        return holdingsText.trim() !== "" && holdingsText.trim() !== "{}"
          ? "No holdings read from " + portfolioPathShort + " — expected {\"bitcoin\": 0.5, …}"
          : "No holdings yet — add coins and amounts under settings (󰒓)"
      if (portfolio.priced === 0 && portfolioFeed.updatedAt)
        return "None of these ids are on CoinGecko — check " + portfolioPathShort
    }
    if (activeFeed.failed) return "CoinGecko unreachable (rate limit?) — retrying at next refresh"
    return activeFeed.retries > 0 ? "CoinGecko is rate limiting — retrying in a moment…" : "Fetching prices…"
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
  // Count changes arrive one click at a time from the settings spinner;
  // settle before asking CoinGecko, which is rate limited per request.
  onCoinCountChanged: countSettle.restart()

  Timer {
    id: countSettle
    interval: 800
    onTriggered: root.refreshMarkets()
  }
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
  // is under a minute old, or when an attempt is already under way or was
  // made within the minute — repeated opens during a rate-limit window
  // must not pile requests into it. The refresh timer and middle-click
  // still force a fetch. The holdings file is local, so re-reading it is
  // always free.
  function refreshIfStale() {
    holdingsFile.reload()
    if (markets.wantsRefresh(60 * 1000)) refreshMarkets()
    if (root.holdingIds !== "" && portfolioFeed.wantsRefresh(60 * 1000)) refreshPortfolio()
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
    // While the panel is writing, the local text is the truth; a read that
    // lands between two queued writes would only roll it back.
    onLoaded: {
      if (root.holdingsWriting) return
      root.portfolioFileFound = true
      root.holdingsText = text()
    }
    onLoadFailed: {
      if (root.holdingsWriting) return
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
    function settings(): void { root.openFromHotkey(); root.openSettings() }
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
    // Header stays put; only the settings body scrolls.
    contentHeight: panel.fittedContentHeight(header.height + Style.space(12) + coinsScroll.bodyHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // A settings field or dropdown owns the keys while it has them.
      blocked: root.settingsOpen && settingsPage.editing
      onCloseRequested: root.settingsOpen ? root.closeSettings() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // Left/Right (h/l) switch tabs; Up/Down (j/k) feature a watchlist coin;
      // 1/2/3 pick the chart range. None of it applies on the settings page.
      onMoveRequested: function(dx, dy) { if (!root.settingsOpen) root.moveCursor(dx, dy) }
      onTextKey: function(t) {
        if (root.settingsOpen) return
        var i = ["1", "2", "3"].indexOf(t)
        if (i >= 0) root.showRange(Model.RANGE_KEYS[i])
      }

      // ---- Header: tabs (or the settings title) on the left, the gear or
      //      its close on the right.
      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(tabRow.height, headerAction.height)

        Row {
          id: tabRow
          visible: !root.settingsOpen
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
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

        Text {
          visible: root.settingsOpen
          anchors.left: parent.left
          anchors.leftMargin: Style.space(22)
          anchors.verticalCenter: parent.verticalCenter
          text: "SETTINGS"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
          font.bold: true
        }

        PanelActionButton {
          id: headerAction
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          iconText: root.settingsOpen ? "󰅖" : "󰒓"
          tooltipText: root.settingsOpen ? "Close settings" : "Settings"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.toggleSettings()
        }
      }

      Flickable {
        id: coinsScroll
        anchors.top: header.bottom
        anchors.topMargin: Style.space(12)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // What the panel is sized to: the coin page's own height, or on the
        // settings page that same height with a floor.
        readonly property real bodyHeight: root.settingsOpen ? Math.max(coinsColumn.implicitHeight, root.settingsMinHeight) : coinsColumn.implicitHeight
        contentWidth: width
        contentHeight: root.settingsOpen ? settingsPage.implicitHeight : coinsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        // Thin foreground-tinted bar at the right edge, only on the settings
        // page and only while there is something to scroll to.
        QQC.ScrollBar.vertical: QQC.ScrollBar {
          id: scrollBar
          policy: root.settingsOpen && coinsScroll.contentHeight > coinsScroll.height ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff
          contentItem: Rectangle {
            implicitWidth: Style.space(4)
            radius: Style.cornerRadius > 0 ? width / 2 : 0
            color: Util.alpha(root.bar.foreground, scrollBar.pressed ? 0.45 : (scrollBar.hovered ? 0.35 : 0.22))
          }
        }

        SettingsPage {
          id: settingsPage
          visible: root.settingsOpen
          width: coinsScroll.width
          panel: root
        }

        Column {
          id: coinsColumn
          visible: !root.settingsOpen
          width: coinsScroll.width
          spacing: Style.space(12)

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
                textFormat: Text.PlainText
                id: heroSymbol
                text: root.hero ? root.hero.title : ""
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                font.letterSpacing: 1
              }
              Text {
                textFormat: Text.PlainText
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
                    textFormat: Text.PlainText
                    text: parent.modelData.label
                    color: Qt.darker(root.bar.foreground, 1.5)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }
                  Text {
                    textFormat: Text.PlainText
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
            textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
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

          // ---- Rows on their way: a lower count or a removed coin apply at
          //      once above; this row stands in for what a higher count or
          //      an added coin is still waiting on.
          Item {
            visible: !root.portfolioView && root.rows.length > 0 && (root.rowsPending || (root.rowsMissing > 0 && markets.failed))
            width: parent.width
            height: Style.space(32)

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                id: fetchSpinner
                visible: !markets.failed
                anchors.verticalCenter: parent.verticalCenter
                text: "󰦖"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall

                RotationAnimator on rotation {
                  running: fetchSpinner.visible
                  from: 0; to: 360
                  duration: 900
                  loops: Animation.Infinite
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: markets.failed ? "CoinGecko unreachable (rate limit?) — retrying at next refresh"
                    : markets.retries > 0 ? "CoinGecko is rate limiting — retrying in a moment…"
                    : "Fetching " + root.rowsMissing + " more…"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.italic: true
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
