# Security Policy

## Supported versions

Only the latest release is supported. Update with `omarchy plugin update ber.omacoins`.

## What this plugin does

Omacoins is a handful of QML/JS files with no build step, no bundled binaries
and no installer. Its full footprint:

- **Network**: outbound HTTPS to two hosts only, via `curl` in a Quickshell
  `Process`. `api.coingecko.com`: `GET /api/v3/coins/markets` per refresh (one
  for the watchlist, one for the portfolio if you keep one) and
  `GET /api/v3/coins/{id}/market_chart` as a fallback. `coins.llama.fi`:
  `GET /chart/...` on demand for the month and year charts. No credentials are
  sent — every endpoint is keyless — and nothing is ever POSTed. Response bodies
  are parsed with `JSON.parse` and never evaluated. Of your data, only CoinGecko
  coin ids leave the machine — never holding amounts.
- **Reads**: the widget's own entry in `~/.config/omarchy/shell.json`, the
  optional `~/.config/omacoins/portfolio.json`, and the active theme's
  `colors.toml` behind `~/.local/state/omarchy/current/theme` (for the up/down
  colors).
- **Writes**: nothing. Settings are changed by you, through `omarchy bar set`.
- **No** `sudo`, `pkexec`, systemd units, package-manager calls, sudoers rules
  or shell-piped downloads.

There is no account, no API key and no telemetry. Prices are public market data.

## Reporting a vulnerability

Please **do not** open a public issue.

Use GitHub's [private vulnerability reporting](https://github.com/bernardcosta/omarchy-omacoins/security/advisories/new),
or email <b.csta@protonmail.com>.

Include what you found, how to reproduce it, and the plugin version from
`manifest.json`. Expect an acknowledgement within a week. This is a
spare-time project, so please allow reasonable time for a fix before public
disclosure.
