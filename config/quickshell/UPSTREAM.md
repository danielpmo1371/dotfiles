# Vendored from Omarchy

`Commons/`, `Ui/`, `plugins/panels/`, `plugins/image-picker/`, `omarchy/bin/`,
`omarchy/default/themed/` (templates) and `omarchy/themes/*/colors.toml` are copied from [basecamp/omarchy](https://github.com/basecamp/omarchy) at
commit `5c4da02` (2026-10-04), MIT licensed (`LICENSE.omarchy`).

Upstream paths: `shell/Commons`, `shell/Ui`, `shell/plugins/...`, `bin/omarchy-*`,
`default/themed/*.tpl`, `themes/<name>/colors.toml` (the themes' wallpapers and
screenshot previews are left out; previews are generated, see below).
Local changes to vendored files are separate commits on top of the verbatim
import, so `git log -- config/quickshell/<path>` shows exactly what differs.
