# Omacoins

Crypto watchlist for the [Omarchy](https://omarchy.org) bar: coin prices and
24h movement, powered by CoinGecko's keyless API. No account, no API key.

- **Bar pill**: a single ₿ glyph by default (hover for the lead coin's
  price), or a full ticker (`BTC $81.2k ▲5.0%`) with `display: "full"`
- **Click** the pill for the full watchlist; **middle-click** to refresh
- Defaults to the top 5 coins by market cap

## Install

```bash
omarchy plugin add <this-repo-url> --enable
```

## Settings

Settings live in the widget's entry in `~/.config/omarchy/shell.json` and
hot-reload on save. The easiest way to change one is the stock command:

```bash
omarchy bar set ber.omacoins display full
omarchy bar set ber.omacoins coins bitcoin,ethereum,solana
omarchy bar set ber.omacoins currency eur
```

Or edit the entry directly:

```jsonc
{
  "id": "ber.omacoins",
  "display": "icon",                   // "icon" = single glyph (default); "full" = price + 24h movement
  "icon": "",                          // icon-mode glyph; default is nf-fa-btc (U+F15A)
  "currency": "usd",                   // fiat base: eur, jpy, gbp, ... (CoinGecko vs_currency)
  "coins": "bitcoin,ethereum,solana",  // CoinGecko ids; empty = top N by market cap
  "count": 5,                          // how many coins to show (1-25)
  "refreshMinutes": 3                  // auto-refresh interval
}
```

### Base currency

`currency` accepts any CoinGecko `vs_currency` code (`usd`, `eur`, `jpy`,
`gbp`, `chf`, `btc`, …); prices, highs/lows, and market caps all follow it.
Common codes get their proper symbol (€, ¥, £); anything unmapped is shown
with its uppercase code. An unsupported code makes the fetch fail — the panel
will say so, and setting a valid code recovers on the spot.

### Bar display modes

- `display: "icon"` (default) — a single icon-slot glyph, for a minimal bar.
  Hover for the lead coin's price; the panel is one click away either way.
- `display: "full"` — lead coin's price and movement right in the bar:
  `BTC $81.2k ▲5.0%`. Enable with `omarchy bar set ber.omacoins display full`.

## Suggested keybinding

Plugins never install keybindings — bindings belong to you, in
`~/.config/hypr/bindings.lua`. To toggle the panel from the keyboard, add:

```lua
-- The unbind is defensive: Hyprland fires ALL binds on a combo, so if a
-- future Omarchy default (or another binding of yours) lands on this key,
-- unbinding first keeps this one exclusive. Unbinding a free key is a no-op.
hl.unbind("SUPER + CTRL + M")
o.bind("SUPER + CTRL + M", "Coins", "omarchy-shell shell toggle ber.omacoins")
```

Pick any free combo; check yours with `omarchy menu keybindings --print`.

## Roadmap

- Portfolio widget: total value and running P&L from a local
  `portfolio.json` (holdings never leave your machine)
- Optional CoinMarketCap API key as an alternative data source
