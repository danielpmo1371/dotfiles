#!/usr/bin/env bash
set -euo pipefail

server="${1:?Usage: $(basename "$0") user@hostname}"
infocmp -x xterm-ghostty | ssh "$server" -- tic -x -

