# Add a LICENSE file

No `LICENSE` at repo root. Blocks "shareable" status independent of the
non-public-data cleanup (issue 16) and the extraction work (issue 14) — the
bootstrap URL in `README.md` is already publicly curl-able with no license
terms attached to what people are cloning.

Pick a permissive license (MIT or Apache-2.0 are the default choices for
dotfiles/tooling repos like this) and add it to the root. Each repo
extracted per issue 14 needs its own copy too.
