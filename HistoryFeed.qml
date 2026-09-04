import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Price history for the 1M and 1Y chart ranges, fetched on demand and
// cached, keyed "id|days". Series are USD; the panel scales them onto the
// live price in the user's currency.
//
// Source of first resort is DefiLlama's chart endpoint: keyless, loosely
// limited, takes CoinGecko ids as they are, and serves several coins per
// request (up to 500 points a call, so one coin for a year of daily
// points, two for a month at four-hour points). Any coin it doesn't
// return — an id it doesn't track, or the whole request failing — is
// refetched one at a time from CoinGecko's /coins/{id}/market_chart,
// which is keyless too but rate limited per IP; those retries are 20s
// apart, three attempts per coin, then a minute's backoff.
//
// want() names coins; anything missing or expired is queued and fetched
// one request at a time. Urgent wants (what is on screen right now) go to
// the front of the queue, ahead of prefetches.
QtObject {
  id: feed

  // "id|days" → { series: [...], at: ms }
  property var cache: ({})
  // Same keys → ms of the last exhausted attempt.
  property var failedAt: ({})
  // Jobs: { ids: [...], days, source: "llama" | "gecko", attempts }.
  property var queue: []
  property var current: null

  function key(id, days) {
    return id + "|" + days
  }

  function series(id, days) {
    var e = cache[key(id, days)]
    return e ? e.series : []
  }

  function failed(id, days) {
    return failedAt[key(id, days)] !== undefined
  }

  function isQueued(id, days) {
    if (current && current.days === days && current.ids.indexOf(id) >= 0) return true
    for (var q = 0; q < queue.length; q++) {
      if (queue[q].days === days && queue[q].ids.indexOf(id) >= 0) return true
    }
    return false
  }

  function want(ids, days, maxAgeMs, urgent) {
    var now = Date.now()
    var needed = []
    for (var i = 0; i < ids.length; i++) {
      var k = key(ids[i], days)
      var e = cache[k]
      if (e && now - e.at < maxAgeMs) continue
      if (failedAt[k] !== undefined && now - failedAt[k] < 60 * 1000) continue
      if (isQueued(ids[i], days)) continue
      needed.push(ids[i])
    }
    if (needed.length === 0) return

    var per = Model.coinsPerChartCall(days)
    var jobs = []
    for (var j = 0; j < needed.length; j += per) {
      jobs.push({ ids: needed.slice(j, j + per), days: days, source: "llama", attempts: 0 })
    }
    queue = urgent ? jobs.concat(queue) : queue.concat(jobs)
    next()
  }

  // Drop queued jobs for any other range: the user moved on, and those
  // requests would only spend rate limit on a chart nobody is looking at.
  // The request in flight is left to finish.
  function keepOnly(days) {
    var kept = []
    for (var i = 0; i < queue.length; i++) if (queue[i].days === days) kept.push(queue[i])
    queue = kept
  }

  function next() {
    if (proc.running || retryTimer.running || spacer.running || queue.length === 0) return
    current = queue.shift()
    var url = current.source === "llama"
      ? Model.llamaChartUrl(current.ids, current.days)
      : Model.marketChartUrl(current.ids[0], current.days, "usd")
    proc.command = Model.curlCommand(url, 15)
    proc.running = true
  }

  function setKey(map, k, value) {
    var out = {}
    for (var p in map) out[p] = map[p]
    if (value === undefined) delete out[k]
    else out[k] = value
    return out
  }

  function store(id, days, series) {
    cache = setKey(cache, key(id, days), { series: series, at: Date.now() })
    failedAt = setKey(failedAt, key(id, days), undefined)
  }

  // Coins DefiLlama didn't deliver go to CoinGecko, one job each, ahead of
  // whatever else is queued: they're the ones someone is waiting on.
  function fallBack(ids, days) {
    var jobs = []
    for (var i = 0; i < ids.length; i++) jobs.push({ ids: [ids[i]], days: days, source: "gecko", attempts: 0 })
    queue = jobs.concat(queue)
  }

  readonly property Timer retryTimer: Timer {
    interval: 20000
    onTriggered: feed.next()
  }

  // A breath between back-to-back requests, so a portfolio's worth
  // doesn't land as a burst.
  readonly property Timer spacer: Timer {
    interval: 300
    onTriggered: feed.next()
  }

  readonly property Process proc: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var job = feed.current
        feed.current = null

        if (job.source === "llama") {
          var got = Model.parseLlamaChart(text)
          var missing = []
          for (var i = 0; i < job.ids.length; i++) {
            if (got[job.ids[i]]) feed.store(job.ids[i], job.days, got[job.ids[i]])
            else missing.push(job.ids[i])
          }
          if (missing.length > 0) feed.fallBack(missing, job.days)
          feed.spacer.restart()
          return
        }

        var parsed = Model.parseMarketChart(text)
        if (parsed.length > 1) {
          feed.store(job.ids[0], job.days, parsed)
          feed.spacer.restart()
          return
        }
        job.attempts++
        if (job.attempts < 3) {
          feed.queue.push(job)
          feed.retryTimer.restart()
        } else {
          feed.failedAt = feed.setKey(feed.failedAt, feed.key(job.ids[0], job.days), Date.now())
          feed.spacer.restart()
        }
      }
    }
  }
}
