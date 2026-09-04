// CoinGecko /coins/markets response → row objects for the panel. Anything
// malformed is dropped rather than surfaced; the panel keeps last-good rows.
function parseMarkets(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!Array.isArray(data)) return []

    var out = []
    for (var i = 0; i < data.length; i++) {
      var c = data[i]
      if (!c || !c.symbol || c.current_price === undefined || c.current_price === null) continue
      out.push({
        id: String(c.id || ""),
        rank: c.market_cap_rank || (i + 1),
        symbol: String(c.symbol).toUpperCase(),
        name: String(c.name || ""),
        price: Number(c.current_price),
        change24h: (c.price_change_percentage_24h === undefined || c.price_change_percentage_24h === null)
          ? null
          : Number(c.price_change_percentage_24h),
        high24h: (c.high_24h === undefined || c.high_24h === null) ? null : Number(c.high_24h),
        low24h: (c.low_24h === undefined || c.low_24h === null) ? null : Number(c.low_24h),
        marketCap: (c.market_cap === undefined || c.market_cap === null) ? null : Number(c.market_cap),
        sparkline: (c.sparkline_in_7d && Array.isArray(c.sparkline_in_7d.price)) ? c.sparkline_in_7d.price : []
      })
    }
    return out
  } catch (e) {
    return []
  }
}

function curlCommand(url, maxTime) {
  return ["curl", "-sS", "--max-time", String(maxTime || 10), url]
}

// Symbols for common CoinGecko vs_currencies; anything unmapped falls back
// to an uppercase code prefix ("CHF 1,234").
var CURRENCY_SYMBOLS = {
  usd: "$", eur: "€", jpy: "¥", gbp: "£", cny: "¥", krw: "₩", inr: "₹",
  brl: "R$", rub: "₽", try: "₺", cad: "C$", aud: "A$", nzd: "NZ$",
  sgd: "S$", hkd: "HK$", mxn: "MX$", btc: "₿", eth: "Ξ"
}

function normalizedCurrency(code) {
  var c = String(code || "usd").toLowerCase().trim()
  return c === "" ? "usd" : c
}

function currencySymbol(code) {
  var c = normalizedCurrency(code)
  return CURRENCY_SYMBOLS[c] !== undefined ? CURRENCY_SYMBOLS[c] : c.toUpperCase() + " "
}

function marketsUrl(customCoins, count, currency) {
  var url = "https://api.coingecko.com/api/v3/coins/markets"
    + "?vs_currency=" + encodeURIComponent(normalizedCurrency(currency))
    + "&order=market_cap_desc"
    + "&page=1"
    + "&price_change_percentage=24h"
    + "&sparkline=true"
    + "&per_page=" + count
  var coins = String(customCoins || "").trim().replace(/\s+/g, "")
  if (coins !== "") url += "&ids=" + encodeURIComponent(coins)
  return url
}

// portfolio.json → [{id, amount}], in file order. Accepts an id→amount map
// ({"bitcoin": 0.5}), an array of {id, amount} entries, or either wrapped in
// a top-level "holdings" key. Ids are CoinGecko ids; a repeated id sums.
// Anything without a positive finite amount is dropped.
function parseHoldings(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (data && typeof data === "object" && !Array.isArray(data) && data.holdings !== undefined)
      data = data.holdings

    var out = []
    var seen = {}
    function add(id, amount) {
      id = String(id || "").trim().toLowerCase()
      var n = Number(amount)
      if (id === "" || !isFinite(n) || n <= 0) return
      if (seen[id] !== undefined) { out[seen[id]].amount += n; return }
      seen[id] = out.length
      out.push({ id: id, amount: n })
    }

    if (Array.isArray(data)) {
      for (var i = 0; i < data.length; i++) {
        var h = data[i]
        if (h && typeof h === "object")
          add(h.id !== undefined ? h.id : h.coin, h.amount !== undefined ? h.amount : h.quantity)
      }
    } else if (data && typeof data === "object") {
      for (var k in data) add(k, data[k])
    }
    return out
  } catch (e) {
    return []
  }
}

function holdingIds(holdings) {
  var ids = []
  for (var i = 0; i < (holdings || []).length; i++) ids.push(holdings[i].id)
  return ids.join(",")
}

// Holdings × market rows → the portfolio: per-coin values, the total, its
// 24h and 7d movement, and a 7-day series of the total for the sparkline.
// Coins CoinGecko didn't return (a typo'd id) are kept as unpriced items so
// the panel can point at them instead of silently shrinking the total.
function buildPortfolio(holdings, rows) {
  var byId = {}
  for (var r = 0; r < (rows || []).length; r++) byId[rows[r].id] = rows[r]

  var items = []
  var total = 0
  var totalAgo = 0
  var priced = 0
  var sparkLen = Infinity
  for (var i = 0; i < (holdings || []).length; i++) {
    var h = holdings[i]
    var c = byId[h.id]
    if (!c) {
      items.push({ id: h.id, amount: h.amount, coin: null, value: null, change24h: null, changeValue24h: null })
      continue
    }
    var value = h.amount * c.price
    var ago = (c.change24h === null || c.change24h <= -100) ? value : value / (1 + c.change24h / 100)
    items.push({ id: h.id, amount: h.amount, coin: c, value: value, change24h: c.change24h, changeValue24h: value - ago })
    total += value
    totalAgo += ago
    priced++
    if (c.sparkline.length > 1) sparkLen = Math.min(sparkLen, c.sparkline.length)
  }

  // Biggest position first; unpriced ids at the end where they read as
  // problems to fix rather than holdings.
  items.sort(function(a, b) {
    if (a.coin && !b.coin) return -1
    if (!a.coin && b.coin) return 1
    return (b.value || 0) - (a.value || 0)
  })

  // Sparklines are hourly but not always the same length, so align them on
  // their most recent point. A coin without one contributes a flat line at
  // its current value, so the series still ends at the live total.
  var sparkline = []
  if (priced > 0 && isFinite(sparkLen)) {
    for (var k = 0; k < sparkLen; k++) {
      var sum = 0
      for (var j = 0; j < items.length; j++) {
        var it = items[j]
        if (!it.coin) continue
        var s = it.coin.sparkline
        sum += it.amount * (s.length > 1 ? s[s.length - sparkLen + k] : it.coin.price)
      }
      sparkline.push(sum)
    }
  }

  var weekAgo = sparkline.length > 1 ? sparkline[0] : null
  return {
    items: items,
    total: total,
    priced: priced,
    missing: items.length - priced,
    change24h: totalAgo > 0 ? (total - totalAgo) / totalAgo * 100 : null,
    changeValue24h: total - totalAgo,
    change7d: weekAgo > 0 ? (total - weekAgo) / weekAgo * 100 : null,
    changeValue7d: weekAgo !== null ? total - weekAgo : null,
    sparkline: sparkline
  }
}

// Chart ranges. 7d rides along with /coins/markets for free. The others
// come from DefiLlama's chart endpoint (keyless, takes CoinGecko ids, at
// most 500 points per request, so `span` also sets how many coins share a
// call), with CoinGecko's per-coin /market_chart as the fallback.
var RANGES = {
  "7d": { label: "7D", days: 7 },
  "30d": { label: "1M", days: 30, span: 180, period: "4h" },
  "1y": { label: "1Y", days: 365, span: 365, period: "1d" }
}
var RANGE_KEYS = ["7d", "30d", "1y"]
var LLAMA_MAX_POINTS = 500

function rangeForDays(days) {
  for (var k in RANGES) if (RANGES[k].days === days) return RANGES[k]
  return null
}

// How many coins fit in one DefiLlama chart request for a range.
function coinsPerChartCall(days) {
  var r = rangeForDays(days)
  if (!r || !r.span) return 1
  return Math.max(1, Math.floor(LLAMA_MAX_POINTS / r.span))
}

function llamaChartUrl(ids, days) {
  var r = rangeForDays(days)
  var keys = []
  for (var i = 0; i < ids.length; i++) keys.push("coingecko:" + ids[i])
  return "https://coins.llama.fi/chart/" + encodeURIComponent(keys.join(","))
    + "?span=" + r.span + "&period=" + r.period
}

// DefiLlama chart response → { coingeckoId: [prices] }. Ids DefiLlama
// doesn't know are simply absent; the caller falls back for those.
function parseLlamaChart(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || !data.coins || typeof data.coins !== "object") return {}
    var out = {}
    for (var key in data.coins) {
      var entry = data.coins[key]
      if (!entry || !Array.isArray(entry.prices)) continue
      var series = []
      for (var i = 0; i < entry.prices.length; i++) {
        var p = entry.prices[i]
        if (!p || p.price === null || p.price === undefined) continue
        var n = Number(p.price)
        if (isFinite(n)) series.push(n)
      }
      if (series.length > 1) out[key.replace(/^coingecko:/, "")] = series
    }
    return out
  } catch (e) {
    return {}
  }
}

// History is kept in USD; the chart is shown in the user's currency by
// scaling so the last point lands on the live price from the market rows.
// Exact for USD, and off only by exchange-rate drift over the range for
// anything else — the shape is what the chart is for.
function scaleSeries(series, livePrice) {
  if (!series || series.length < 2) return []
  var last = series[series.length - 1]
  var live = Number(livePrice)
  if (!(last > 0) || !isFinite(live) || !(live > 0)) return series
  var factor = live / last
  var out = []
  for (var i = 0; i < series.length; i++) out.push(series[i] * factor)
  return out
}

function normalizedRange(value) {
  var r = String(value || "").toLowerCase().trim()
  return RANGES[r] !== undefined ? r : "7d"
}

function marketChartUrl(id, days, currency) {
  return "https://api.coingecko.com/api/v3/coins/" + encodeURIComponent(String(id || ""))
    + "/market_chart?vs_currency=" + encodeURIComponent(normalizedCurrency(currency))
    + "&days=" + days
}

// /coins/{id}/market_chart response → plain price series. Timestamps are
// dropped: the chart is shape-only, and series are aligned by index from
// their most recent point.
function parseMarketChart(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || !Array.isArray(data.prices)) return []
    var out = []
    for (var i = 0; i < data.prices.length; i++) {
      var p = data.prices[i]
      if (!Array.isArray(p) || p.length < 2 || p[1] === null) continue
      var n = Number(p[1])
      if (isFinite(n)) out.push(n)
    }
    return out
  } catch (e) {
    return []
  }
}

// Sum of amount × price across several series, aligned on their most
// recent point. A shorter series (a coin younger than the range, or one
// point short) is padded at the front with its first value.
function sumSeries(parts) {
  var len = 0
  for (var i = 0; i < (parts || []).length; i++) {
    if (parts[i].series.length > 1) len = Math.max(len, parts[i].series.length)
  }
  if (len === 0) return []
  var out = []
  for (var k = 0; k < len; k++) {
    var sum = 0
    for (var j = 0; j < parts.length; j++) {
      var s = parts[j].series
      if (s.length === 0) continue
      var idx = s.length - len + k
      sum += parts[j].amount * s[idx < 0 ? 0 : idx]
    }
    out.push(sum)
  }
  return out
}

// Percentage move from the start of a series to the live value.
function rangeChange(series, current) {
  if (!series || series.length < 2 || !(series[0] > 0) || !isFinite(Number(current))) return null
  return (Number(current) - series[0]) / series[0] * 100
}

function thousands(n) {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

// Full price for the panel rows. Sub-unit coins keep enough precision to
// be meaningful; everything else reads like a fiat amount.
function formatPrice(value, sym) {
  var n = Number(value)
  if (isNaN(n)) return ""
  if (sym === undefined) sym = "$"
  if (n >= 1000) return sym + thousands(Math.round(n))
  if (n >= 1) return sym + n.toFixed(2)
  if (n >= 0.01) return sym + n.toFixed(4)
  return sym + n.toFixed(6)
}

// Compact price for the bar pill, where width is precious. The M tier keeps
// weak-unit currencies readable (BTC in JPY is an eight-digit number).
function compactPrice(value, sym) {
  var n = Number(value)
  if (isNaN(n)) return ""
  if (sym === undefined) sym = "$"
  if (n >= 1e6) return sym + (n / 1e6).toFixed(2) + "M"
  if (n >= 10000) return sym + (n / 1000).toFixed(1) + "k"
  if (n >= 1000) return sym + thousands(Math.round(n))
  if (n >= 1) return sym + n.toFixed(2)
  return sym + n.toFixed(4)
}

// Market cap in the shortest readable form: "$1.63T", "$245.1B", "$980M".
function compactCap(value, sym) {
  var n = Number(value)
  if (isNaN(n) || n <= 0) return ""
  if (sym === undefined) sym = "$"
  if (n >= 1e15) return sym + (n / 1e15).toFixed(2) + "Q"
  if (n >= 1e12) return sym + (n / 1e12).toFixed(2) + "T"
  if (n >= 1e9) return sym + (n / 1e9).toFixed(1) + "B"
  if (n >= 1e6) return sym + Math.round(n / 1e6) + "M"
  return sym + thousands(Math.round(n))
}

// Signed percentage for the panel rows: "+1.2%" / "-0.8%".
function formatChange(change) {
  if (change === null || change === undefined || isNaN(Number(change))) return ""
  var n = Number(change)
  return (n >= 0 ? "+" : "") + n.toFixed(1) + "%"
}

// Bar pill text for the lead coin: "BTC $109.3k ▲1.2%".
function barLabel(rows, sym) {
  if (!rows || rows.length === 0) return ""
  var c = rows[0]
  var label = c.symbol + " " + compactPrice(c.price, sym)
  if (c.change24h !== null && !isNaN(Number(c.change24h))) {
    var arrow = c.change24h >= 0 ? "▲" : "▼"
    label += " " + arrow + Math.abs(c.change24h).toFixed(1) + "%"
  }
  return label
}

// Holding size: "0.5", "2", "10,000", "0.000123". Six significant figures
// is enough to tell positions apart without turning into noise.
function formatAmount(value) {
  var n = Number(value)
  if (!isFinite(n)) return ""
  if (n >= 1000) return thousands(Math.round(n))
  var s = String(parseFloat(n.toPrecision(6)))
  return s.indexOf("e") >= 0 ? n.toFixed(8) : s
}

// Signed money movement for the portfolio stats: "+$1.2k" / "-€45.20".
function formatSigned(value, sym) {
  var n = Number(value)
  if (!isFinite(n)) return ""
  if (sym === undefined) sym = "$"
  var abs = Math.abs(n)
  var sign = n < 0 ? "-" : "+"
  // Movements are fiat amounts: cents matter under a hundred, whole units
  // above it, and the compact k/M tiers past a thousand.
  if (abs >= 1000) return sign + compactPrice(abs, sym)
  if (abs >= 100) return sign + sym + Math.round(abs)
  return sign + sym + abs.toFixed(2)
}

// ---- View models. The panel draws one hero block and one row list for
// both tabs, so these shape a coin or a portfolio into the same fields:
//   hero: { title, subtitle, change, price, sparkline, stats: [{label, value}] }
//   row:  { key, lead, symbol, detail, value, change, selectable }

function coinHero(coin, sym, series) {
  if (!coin) return null
  return {
    title: coin.symbol,
    subtitle: coin.name.toUpperCase(),
    change: coin.change24h,
    price: formatPrice(coin.price, sym),
    sparkline: series !== undefined ? series : coin.sparkline,
    stats: [
      { label: "HIGH", value: coin.high24h !== null ? compactPrice(coin.high24h, sym) : "—" },
      { label: "LOW", value: coin.low24h !== null ? compactPrice(coin.low24h, sym) : "—" },
      { label: "MCAP", value: compactCap(coin.marketCap, sym) || "—" }
    ]
  }
}

function portfolioHero(portfolio, sym, series, rangeLabel) {
  if (!portfolio || portfolio.priced === 0) return null
  var top = portfolio.items[0]
  var share = portfolio.total > 0 ? Math.round(top.value / portfolio.total * 100) : 0
  if (series === undefined) series = portfolio.sparkline
  if (rangeLabel === undefined) rangeLabel = "7D"
  return {
    title: "TOTAL",
    subtitle: "",
    change: portfolio.change24h,
    price: formatPrice(portfolio.total, sym),
    sparkline: series,
    stats: [
      { label: "24H", value: formatSigned(portfolio.changeValue24h, sym) },
      { label: rangeLabel, value: series.length > 1 ? formatSigned(portfolio.total - series[0], sym) : "—" },
      { label: "TOP", value: top.coin.symbol + " " + share + "%" }
    ]
  }
}

function watchlistRows(rows, sym) {
  var out = []
  for (var i = 0; i < (rows || []).length; i++) {
    var c = rows[i]
    out.push({
      key: c.id,
      lead: String(c.rank),
      symbol: c.symbol,
      detail: c.name,
      value: formatPrice(c.price, sym),
      change: c.change24h,
      selectable: true
    })
  }
  return out
}

function portfolioRows(portfolio, sym) {
  var out = []
  var items = portfolio ? portfolio.items : []
  for (var i = 0; i < items.length; i++) {
    var it = items[i]
    if (it.coin) {
      out.push({
        key: it.id,
        lead: "",
        symbol: it.coin.symbol,
        detail: formatAmount(it.amount) + " · " + formatPrice(it.coin.price, sym),
        value: formatPrice(it.value, sym),
        change: it.change24h,
        selectable: false
      })
    } else {
      out.push({
        key: it.id,
        lead: "",
        symbol: it.id.toUpperCase(),
        detail: formatAmount(it.amount) + " · not a CoinGecko id",
        value: "—",
        change: null,
        selectable: false
      })
    }
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    parseMarkets: parseMarkets,
    marketsUrl: marketsUrl,
    normalizedCurrency: normalizedCurrency,
    currencySymbol: currencySymbol,
    thousands: thousands,
    formatPrice: formatPrice,
    compactCap: compactCap,
    compactPrice: compactPrice,
    formatChange: formatChange,
    barLabel: barLabel,
    parseHoldings: parseHoldings,
    holdingIds: holdingIds,
    buildPortfolio: buildPortfolio,
    formatAmount: formatAmount,
    formatSigned: formatSigned,
    coinHero: coinHero,
    portfolioHero: portfolioHero,
    watchlistRows: watchlistRows,
    portfolioRows: portfolioRows,
    RANGES: RANGES,
    RANGE_KEYS: RANGE_KEYS,
    normalizedRange: normalizedRange,
    marketChartUrl: marketChartUrl,
    parseMarketChart: parseMarketChart,
    sumSeries: sumSeries,
    rangeChange: rangeChange,
    curlCommand: curlCommand,
    coinsPerChartCall: coinsPerChartCall,
    llamaChartUrl: llamaChartUrl,
    parseLlamaChart: parseLlamaChart,
    scaleSeries: scaleSeries
  }
}
