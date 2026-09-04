# Contributing to Omacoins

Bug reports, coin-formatting edge cases and small focused PRs are all welcome.
For anything larger than a bug fix, please open an issue first so we can agree
on the shape before you spend time on it.

## Getting a development copy

The plugin has no build step — it is QML and plain JavaScript, loaded by
`omarchy-shell` at runtime. Point Omarchy at your fork and edit in place:

```bash
omarchy plugin add https://github.com/<you>/omarchy-omacoins --enable
cd ~/.config/omarchy/plugins/ber.omacoins
git remote set-url origin git@github.com:<you>/omarchy-omacoins.git
```

Editing the files in that directory edits the live plugin.

## The one gotcha that will waste your afternoon

**After editing any `.qml` file, run `omarchy-restart-shell` before judging the
result.** The shell logs `Local plugin changed, reloading: ber.omacoins` on
save, but the QML engine keeps serving its cached compilation — your visual
change silently does not apply, and you will debug code that is not running.

Do **not** use `omarchy-refresh-shell`: it resets `shell.json` to defaults and
wipes the widget's configuration.

Changes to `shell.json` settings hot-reload correctly, no restart needed.

## Useful commands

```bash
omarchy bar set ber.omacoins <key> <value>   # change a setting ("" restores the default)
omarchy-shell shell toggle ber.omacoins      # drive the panel over IPC (also open/close/refresh)
omarchy plugin validate .                    # check manifest.json against the plugin schema
```

A headless syntax check, without restarting your shell:

```bash
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen qml6 Panel.qml
```

Without `QT_FORCE_STDERR_LOGGING=1`, console output goes to journald and the
run looks misleadingly silent.

## Architecture — please keep the layering

Three files, and the boundaries between them are load-bearing:

- **`BarWidget.qml`** — the manifest entry point mounted in the bar.
  Deliberately thin: it draws the bar pill and loads `Panel.qml` through a
  `Loader`. Two contracts must be preserved. `injectPanel()` pushes `bar`,
  `settings`, `anchorItem` and `hostWidget` into the loaded panel, and re-runs
  on `onBarChanged`/`onSettingsChanged` because the panel is nested rather than
  a direct bar child. And because the bar identifies panels by the widget in
  its slot, `opened`, `open()`, `close()`, `popoutSwitchClosing` and
  `closeForPopoutSwitch()` must stay forwarded from the panel to this root —
  `Bar.findPanelWidget` and `Bar.requestPopout` require them there.
- **`Panel.qml`** — all state and behaviour: settings parsing, the fetch state
  machine, theme colours, and the popup UI.
- **`Model.js`** — pure functions only. No QML imports, no side effects. It has
  a `module.exports` guard so it can be exercised directly:

  ```bash
  node -e "const m = require('./Model.js'); console.log(m.formatPrice(81601, 'usd'))"
  ```

  There is no test suite; if you change formatting, please paste a few `node -e`
  results into your PR.

## Touching the fetch path

CoinGecko's keyless endpoint is rate limited per IP, and most of the state
machine exists to respect that: last-good rows survive a failure, retries are
spaced 20s apart with a budget of 3 per cycle, `refreshIfStale()` skips a fetch
on data under a minute old, `fetchQueued` handles a settings change landing
mid-flight, and `refreshMinutes` clamps to a 1-minute floor. Please do not
loosen any of these — a plugin that hammers the endpoint gets everyone's IP
throttled.

One request covers price, 24h change and sparkline for every coin listed, so
coin count never costs extra requests. Keep it that way.

## Theming

Up/down colours are read from the active theme's `colors.toml` (`green`/`red`).
Everything else derives from `root.bar.foreground` and the `Style`/`Color`
singletons — **do not hardcode palette values**; the two fallback hex colours
are the only sanctioned exception. Theme swaps retarget a symlink, which a
plain file watch misses, so they are detected via `Connections` on the shell's
`Color` singleton.

## Commits and versioning

Releases are cut by [semantic-release](https://semantic-release.gitbook.io/) on
every push to `main`, so commit messages are the release input. Use
[Conventional Commits](https://www.conventionalcommits.org/):

- `fix: ...` → patch release
- `feat: ...` → minor release
- `feat!: ...` or a `BREAKING CHANGE:` footer → major release
- `docs:`, `chore:`, `refactor:`, `style:` → no release

**Never bump the version by hand.** `manifest.json` and `CHANGELOG.md` are
rewritten by the release job; editing them in a PR will conflict.

## Pull requests

Base your branch on `main`. Keep PRs to one concern, describe what you changed
and how you verified it on a running shell, and include a screenshot for
anything visual. Please confirm you ran `omarchy-restart-shell` before judging
the result — it is the most common source of "works on my machine".

By contributing you agree that your work is licensed under the [MIT
License](LICENSE).
