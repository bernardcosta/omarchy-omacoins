import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Watchlist popup: coin prices and 24h movement from CoinGecko's keyless
// /coins/markets endpoint. Settings (shell.json entry for ber.omacoins):
//   coins:          comma-separated CoinGecko ids ("bitcoin,solana");
//                   empty means top N by market cap
//   count:          how many coins to show (default 5)
//   refreshMinutes: auto-refresh interval (default 3)
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

  // Parsed market rows. Kept on failure so stale data stays visible.
  property var rows: []
  property var updatedAt: null
  property int fetchRetries: 0
  property bool fetchFailed: false
  // Set when a refresh arrives while a fetch is in flight (e.g. the currency
  // was changed mid-request); the finishing fetch immediately starts another.
  property bool fetchQueued: false

  // Bar pill text, updated with each successful response.
  property string label: ""

  readonly property string customCoins: String(setting("coins", "")).trim()
  readonly property string currency: Model.normalizedCurrency(setting("currency", "usd"))
  readonly property string currencySymbol: Model.currencySymbol(currency)
  readonly property int coinCount: Math.max(1, Math.min(25, parseInt(setting("count", 5), 10) || 5))
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 3), 10) || 3)

  readonly property color upColor: "#7fbf7f"
  readonly property color downColor: "#e07a7a"

  readonly property string watchlistTitle: customCoins !== "" ? "WATCHLIST" : ("TOP " + coinCount + " BY MARKET CAP")

  // Featured coin shown in the hero; clicking a watchlist row changes it.
  property int selectedIndex: 0
  readonly property var hero: rows.length > 0 ? rows[Math.min(selectedIndex, rows.length - 1)] : null

  // A settings edit (different coins or count) should refetch immediately,
  // not wait out the refresh timer.
  onCustomCoinsChanged: Qt.callLater(refresh)
  onCoinCountChanged: Qt.callLater(refresh)
  onCurrencyChanged: Qt.callLater(refresh)

  function refresh() {
    // Each refresh cycle gets a fresh retry budget, so an earlier exhausted
    // round (e.g. waking with the network still down) doesn't starve retries
    // for the rest of the session.
    fetchRetries = 0
    startFetch()
  }

  // Opening the panel shouldn't burn a rate-limited API call when the data
  // is under a minute old; the refresh timer and middle-click still force it.
  function refreshIfStale() {
    if (updatedAt && (Date.now() - updatedAt.getTime()) < 60 * 1000) return
    refresh()
  }

  function startFetch() {
    if (marketsProc.running) {
      fetchQueued = true
      return
    }
    marketsProc.command = ["curl", "-fsS", "--max-time", "10",
      Model.marketsUrl(root.customCoins, root.coinCount, root.currency)]
    marketsProc.running = true
  }

  function scheduleFetchRetry() {
    if (fetchRetries >= 3) {
      fetchFailed = true
      return
    }
    fetchRetries++
    fetchRetryTimer.restart()
  }

  function changeColor(change) {
    if (change === null || change === undefined) return Qt.darker(root.bar.foreground, 1.5)
    return change >= 0 ? upColor : downColor
  }

  function badgeFill(change) {
    var c = changeColor(change)
    return Qt.rgba(c.r, c.g, c.b, 0.16)
  }

  Process {
    id: marketsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var wasQueued = root.fetchQueued
        root.fetchQueued = false

        var parsed = Model.parseMarkets(text)
        if (parsed.length === 0) {
          // Keep last-good rows visible, but try again shortly.
          root.scheduleFetchRetry()
          return
        }
        root.rows = parsed
        root.label = Model.barLabel(parsed, root.currencySymbol)
        root.updatedAt = new Date()
        root.fetchRetries = 0
        root.fetchFailed = false
        // A queued refresh means these results were requested with settings
        // that have since changed — refetch with the current ones.
        if (wasQueued) Qt.callLater(root.startFetch)
      }
    }
  }

  // Generous spacing between retries: the usual failure is CoinGecko's
  // per-IP rate limit, which hammering only prolongs.
  Timer {
    id: fetchRetryTimer
    interval: 20000
    onTriggered: root.startFetch()
  }

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

          Text {
            visible: !root.hero
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            text: root.fetchFailed ? "CoinGecko unreachable (rate limit?) — retrying at next refresh" : "Fetching prices…"
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.italic: true
          }

          // ---- Hero: featured coin — identity + change badge on the left,
          //      HIGH/LOW/MCAP stat columns on the right, and the big price
          //      on its own full-width row beneath (weather-hero style).
          Item {
            id: heroRow
            visible: !!root.hero
            width: parent.width
            height: Math.max(heroIdentity.height, heroStats.height)

            // Room the featured coin's identity line has before it would run
            // under the HIGH/LOW/MCAP columns.
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
                text: root.hero ? root.hero.symbol : ""
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                font.letterSpacing: 1
              }
              Text {
                id: heroName
                anchors.verticalCenter: heroSymbol.verticalCenter
                // advanceWidth, not width: the bounding rect comes up a
                // few px short on letter-spaced text and elides needlessly.
                width: Math.min(heroNameMetrics.advanceWidth + Style.space(4),
                                Math.max(0, heroRow.leftRoom - heroSymbol.width
                                            - heroBadge.width - Style.space(16)))
                elide: Text.ElideRight
                text: root.hero ? root.hero.name.toUpperCase() : ""
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                font.letterSpacing: 1
              }

              Rectangle {
                id: heroBadge
                visible: root.hero && root.hero.change24h !== null
                anchors.verticalCenter: heroSymbol.verticalCenter
                width: heroBadgeText.implicitWidth + Style.space(14)
                height: heroBadgeText.implicitHeight + Style.space(6)
                radius: height / 2
                color: root.hero ? root.badgeFill(root.hero.change24h) : "transparent"

                Text {
                  id: heroBadgeText
                  anchors.centerIn: parent
                  text: root.hero ? Model.formatChange(root.hero.change24h) : ""
                  color: root.hero ? root.changeColor(root.hero.change24h) : "transparent"
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

              Column {
                spacing: Style.space(5)
                Text {
                  text: "HIGH"
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
                Text {
                  text: root.hero && root.hero.high24h !== null ? Model.compactPrice(root.hero.high24h, root.currencySymbol) : "—"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.subtitle
                }
              }

              Column {
                spacing: Style.space(5)
                Text {
                  text: "LOW"
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
                Text {
                  text: root.hero && root.hero.low24h !== null ? Model.compactPrice(root.hero.low24h, root.currencySymbol) : "—"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.subtitle
                }
              }

              Column {
                spacing: Style.space(5)
                Text {
                  text: "MCAP"
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
                Text {
                  text: root.hero ? (Model.compactCap(root.hero.marketCap, root.currencySymbol) || "—") : "—"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.subtitle
                }
              }
            }
          }

          // ---- Big price on its own row: full width at its designed size.
          //      HorizontalFit stays as the fallback, so it only shrinks if
          //      the price outgrows the panel itself.
          Text {
            id: heroPrice
            visible: !!root.hero
            x: Style.space(16)
            width: parent.width - Style.space(32)
            text: root.hero ? Model.formatPrice(root.hero.price, root.currencySymbol) : ""
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

          // ---- 7-day sparkline for the featured coin.
          Canvas {
            id: spark
            visible: series.length > 1
            width: parent.width - Style.space(32)
            height: Style.space(44)
            anchors.horizontalCenter: parent.horizontalCenter

            readonly property var series: root.hero ? root.hero.sparkline : []
            readonly property color lineColor: series.length > 1 && series[series.length - 1] >= series[0] ? root.upColor : root.downColor

            onSeriesChanged: requestPaint()
            onLineColorChanged: requestPaint()

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

          Item {
            visible: !!root.hero
            width: parent.width
            height: sparkCaption.implicitHeight

            Text {
              id: sparkCaption
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              text: "7 DAYS"
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }
          }

          // ---- Divider between hero and watchlist.
          Rectangle {
            visible: root.rows.length > 0
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
          }

          Item {
            visible: root.rows.length > 0
            width: parent.width
            height: headerTitle.implicitHeight

            Text {
              id: headerTitle
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              text: root.watchlistTitle
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

          // ---- Coin rows: rank + symbol + name left, price + change badge
          //      right. Hover highlights; clicking features the coin above.
          Column {
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.rows

              Rectangle {
                required property var modelData
                required property int index
                width: parent.width
                height: Style.space(32)
                radius: Style.cornerRadius
                color: rowArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

                Text {
                  id: rankText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(22)
                  text: String(modelData.rank)
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
                  color: index === root.selectedIndex ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.1)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }

                Text {
                  anchors.left: symbolText.right
                  anchors.right: priceText.left
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.name
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
                  text: Model.formatPrice(modelData.price, root.currencySymbol)
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
                  color: root.badgeFill(modelData.change24h)

                  Text {
                    id: changeText
                    anchors.centerIn: parent
                    text: Model.formatChange(modelData.change24h) || "—"
                    color: root.changeColor(modelData.change24h)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }

                MouseArea {
                  id: rowArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectedIndex = index
                }
              }
            }
          }

          // ---- Divider + footer
          Rectangle {
            visible: root.rows.length > 0
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
          }

          Item {
            visible: root.rows.length > 0
            width: parent.width
            height: footerText.implicitHeight

            Text {
              id: footerText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              text: "CoinGecko" + (root.updatedAt ? " · updated " + Qt.formatTime(root.updatedAt, "HH:mm") : "")
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
