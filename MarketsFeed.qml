import QtQuick
import Quickshell.Io
import "Model.js" as Model

// One CoinGecko /coins/markets feed: the curl Process plus the retry and
// queueing discipline the keyless endpoint's per-IP rate limit calls for.
// Panel.qml runs two of these — the watchlist and the portfolio — so the
// rules live here once:
//
// - Last-good rows survive a failed response, so stale data stays visible.
// - Retries are 20s apart, at most 3 per fetch(); the usual failure is the
//   rate limit, which hammering only prolongs.
// - fetch() while a request is in flight queues one more, carrying the URL
//   and symbol given last, so a settings change landing mid-request still
//   takes effect. A queued request identical to the one just completed is
//   dropped: its answer is already the freshest there is.
// - The currency symbol travels with the request and is published only
//   with the rows priced in it, so a currency change never relabels the
//   previous currency's numbers.
QtObject {
  id: feed

  property var rows: []
  property var updatedAt: null
  property bool failed: false
  property int retries: 0
  property bool queued: false
  // Symbol the published rows were priced in; empty until the first success.
  property string rowsSymbol: ""
  property string pendingUrl: ""
  property string pendingSymbol: ""
  property string queuedUrl: ""
  property string queuedSymbol: ""

  readonly property bool running: proc.running

  // A fresh fetch cycle: new retry budget, then the request.
  function fetch(url, symbol) {
    retries = 0
    request(url, symbol)
  }

  function isStale(maxAgeMs) {
    return !updatedAt || (Date.now() - updatedAt.getTime()) >= maxAgeMs
  }

  // Drop everything, including a pending retry. Used when the feed has
  // nothing left to fetch (an emptied portfolio).
  function clear() {
    retryTimer.stop()
    queued = false
    rows = []
    updatedAt = null
    failed = false
    retries = 0
    rowsSymbol = ""
  }

  function request(url, symbol) {
    if (proc.running) {
      queued = true
      queuedUrl = url
      queuedSymbol = symbol
      return
    }
    retryTimer.stop()
    // Captured now, not read on completion: the settings can change while
    // the request is in the air, and these results belong to the old ones.
    pendingUrl = url
    pendingSymbol = symbol
    proc.command = Model.curlCommand(url, 10)
    proc.running = true
  }

  function scheduleRetry() {
    if (retries >= 3) {
      failed = true
      return
    }
    retries++
    retryTimer.restart()
  }

  readonly property Timer retryTimer: Timer {
    interval: 20000
    onTriggered: feed.request(feed.pendingUrl, feed.pendingSymbol)
  }

  readonly property Process proc: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var wasQueued = feed.queued
        feed.queued = false
        var refetch = wasQueued && (feed.queuedUrl !== feed.pendingUrl || feed.queuedSymbol !== feed.pendingSymbol)

        var parsed = Model.parseMarkets(text)
        // An empty array is a real answer (none of the requested ids exist),
        // not a failure to retry.
        if (parsed.length === 0 && String(text).trim() !== "[]") {
          // Keep last-good rows visible, but try again shortly — with the
          // queued request if there is one, since that reflects the
          // current settings.
          if (refetch) {
            feed.pendingUrl = feed.queuedUrl
            feed.pendingSymbol = feed.queuedSymbol
          }
          feed.scheduleRetry()
          return
        }
        feed.rowsSymbol = feed.pendingSymbol
        feed.rows = parsed
        feed.updatedAt = new Date()
        feed.retries = 0
        feed.failed = false
        if (refetch) Qt.callLater(function() { feed.request(feed.queuedUrl, feed.queuedSymbol) })
      }
    }
  }
}
