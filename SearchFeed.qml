import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Coin lookup for the settings page: what the user types → CoinGecko ids,
// via the keyless /search endpoint. It shares the per-IP budget with the
// price feeds, so typing must not turn into a request per keystroke:
//
// - Queries are debounced, and only one request is in flight at a time. A
//   query that moved on while one was out is fetched once that returns.
// - A query under two characters is answered locally with nothing.
// - A body that is not a search result (the rate limiter answers with a
//   status object) is reported as `failed`, so the page can say so rather
//   than show "no matches" for a coin that exists.
QtObject {
  id: feed

  property var results: []
  // Query the current results answer; empty until the first response.
  property string query: ""
  property bool failed: false
  property string pending: ""
  property string active: ""

  readonly property bool busy: proc.running || debounce.running

  function search(text) {
    var q = String(text || "").trim()
    if (q.length < 2) {
      clear()
      return
    }
    pending = q
    debounce.restart()
  }

  function clear() {
    debounce.stop()
    pending = ""
    results = []
    failed = false
    query = ""
  }

  function start() {
    if (proc.running || pending === "") return
    if (pending === query && !failed) return
    active = pending
    proc.command = Model.curlCommand(Model.searchUrl(active), 8)
    proc.running = true
  }

  readonly property Timer debounce: Timer {
    interval: 350
    onTriggered: feed.start()
  }

  readonly property Process proc: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Cleared while in flight (a suggestion was picked): the answer is
        // for a question nobody is asking any more.
        if (feed.pending === "") return
        var parsed = Model.parseSearch(text)
        if (feed.pending === feed.active) {
          feed.query = feed.active
          feed.results = parsed === null ? [] : parsed
          feed.failed = parsed === null
        } else {
          Qt.callLater(feed.start)
        }
      }
    }
  }
}
