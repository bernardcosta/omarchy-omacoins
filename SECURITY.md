# Security Policy

## Supported versions

Only the latest release is supported. Update with `omarchy plugin update ber.omacoins`.

## What this plugin does

Omacoins is three QML/JS files with no build step, no bundled binaries and no
installer. Its full footprint:

- **Network**: outbound HTTPS to `api.coingecko.com` only, via `curl` in a
  Quickshell `Process`. One `GET /api/v3/coins/markets` per refresh. No
  credentials are sent — the endpoint is keyless — and nothing is ever POSTed.
  Response bodies are parsed with `JSON.parse` and never evaluated.
- **Reads**: the widget's own entry in `~/.config/omarchy/shell.json`, and the
  active theme's `colors.toml` behind `~/.local/state/omarchy/current/theme`
  (for the up/down colors).
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
