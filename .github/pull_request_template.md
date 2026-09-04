## What this changes

<!-- One or two sentences. Link the issue if there is one: Fixes #123 -->

## How I verified it

<!-- Which display modes / settings you exercised. Screenshot for anything visual. -->

## Checklist

- [ ] Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (`fix:`, `feat:`, `docs:`, …) — releases are cut from them
- [ ] I did **not** hand-edit the version in `manifest.json` or `CHANGELOG.md`
- [ ] I ran `omarchy-restart-shell` after editing `.qml` and judged the result on a restarted shell
- [ ] `omarchy plugin validate .` passes
- [ ] `Model.js` still has no QML imports and no side effects (if touched)
- [ ] No hardcoded palette colours — theme values only
- [ ] The fetch path still makes at most one CoinGecko request per refresh
