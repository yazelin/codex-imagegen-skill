#!/usr/bin/env bash
# codex-imagegen — generate an image via Codex CLI's $imagegen shorthand,
# then copy it from Codex's session-scoped output dir to a path you choose.
#
# Usage:  codex-imagegen.sh "<prompt>" "<target-path>"
#
# Requires:
#   - `codex` CLI installed and authenticated (`codex login`)
#   - the user's Codex generated-images dir at $CODEX_HOME (default: ~/.codex)
#
# On success: prints the absolute path of the saved PNG.
# On failure: writes an error to stderr and exits non-zero.

set -euo pipefail

PROMPT="${1:?usage: codex-imagegen.sh <prompt> <target-path>}"
TARGET="${2:?usage: codex-imagegen.sh <prompt> <target-path>}"

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

mkdir -p "$(dirname "$TARGET")"

OUT=$(codex exec -C "$(pwd)" -s workspace-write --skip-git-repo-check \
        "\$imagegen $PROMPT" 2>&1)

SID=$(printf '%s\n' "$OUT" | grep -oE 'session id: [a-f0-9-]+' | head -1 | awk '{print $3}')
if [[ -z "$SID" ]]; then
  echo "ERROR: failed to extract session id from codex output" >&2
  echo "--- codex output ---" >&2
  printf '%s\n' "$OUT" >&2
  exit 1
fi

SRC_DIR="$CODEX_HOME/generated_images/$SID"
SRC=$(ls -t "$SRC_DIR"/*.png 2>/dev/null | head -1 || true)
if [[ -z "$SRC" ]]; then
  echo "ERROR: no PNG found in $SRC_DIR" >&2
  echo "(codex reported success but the output directory is empty — try re-running)" >&2
  exit 1
fi

cp "$SRC" "$TARGET"
realpath "$TARGET"
