# Security Policy

## Supported versions

Only the latest release is supported. Update with `omarchy plugin update ber.omacoins`.

## What this plugin does

Omacoins is a handful of QML/JS files with no build step, no bundled binaries
and no installer. Its full footprint:

- **Network**: outbound HTTPS to two hosts only, via `curl` in a Quickshell
  `Process`. `api.coingecko.com`: `GET /api/v3/coins/markets` per refresh (one
  for the watchlist, one for the portfolio if you keep one),
  `GET /api/v3/coins/{id}/market_chart` as a chart fallback and
  `GET /api/v3/search` for the settings page's coin autocomplete.
  `coins.llama.fi`: `GET /chart/...` on demand for the month and year charts.
  No credentials are sent — every endpoint is keyless — and nothing is ever
  POSTed. Of your data, only CoinGecko coin ids and what you type into the
  coin search leave the machine — never holding amounts.
- **Response handling**: every `curl` runs with `--proto =https` (no
  downgrade, even via redirect), a wall-clock timeout and `--max-filesize`
  of 2 MiB, so an oversize body is cut off mid-transfer and discarded. Bodies
  are parsed with `JSON.parse`, never evaluated, and the parsers cap what they
  keep (250 rows, 200 sparkline points, 1000 chart points, 100 coins per chart
  answer); anything malformed or truncated is dropped and the last good data
  stays on screen.
- **Reads**: the widget's own entry in `~/.config/omarchy/shell.json`, the
  holdings file (`~/.config/omacoins/portfolio.json` by default, or the path in
  the `portfolio` setting), and the active theme's `colors.toml` behind
  `~/.local/state/omarchy/current/theme` (for the up/down colors).
- **Writes**: two things, both only when you edit them in the settings page.
  The widget's own settings go through the shell's `updateEntryInline`, the
  same path as `omarchy bar set`. The holdings file is rewritten whole: the
  text is written to an exclusive `mktemp` file (mode 0600, unpredictable
  name) in the target directory and renamed over the destination, so a planted
  symlink at a guessable temp name cannot redirect the write and a symlink at
  the destination is replaced rather than followed. Nothing outside those two
  files is touched.
- **No** `sudo`, `pkexec`, systemd units, package-manager calls, sudoers rules
  or shell-piped downloads.

## Release pipeline

Releases are cut by GitHub Actions on `main`. The workflow has `contents:
write` only, pins both actions to full commit SHAs, installs semantic-release
and its plugins from the committed `package-lock.json` with `npm ci
--ignore-scripts`, and runs it without a network install. None of this ships
to users: the plugin is the QML/JS files in this repository, nothing is built.

There is no account, no API key and no telemetry. Prices are public market data.

## Reporting a vulnerability

Please **do not** open a public issue.

Use GitHub's [private vulnerability reporting](https://github.com/bernardcosta/omarchy-omacoins/security/advisories/new),
or email <b.csta@protonmail.com>.

Include what you found, how to reproduce it, and the plugin version from
`manifest.json`. Expect an acknowledgement within a week. This is a
spare-time project, so please allow reasonable time for a fix before public
disclosure.
