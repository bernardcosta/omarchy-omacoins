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
    barLabel: barLabel
  }
}
