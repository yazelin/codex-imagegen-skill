#!/usr/bin/env bash
# codex-imagegen — generate or edit an image via Codex CLI's $imagegen shorthand,
# then copy it from Codex's session-scoped output dir to a path you choose.
#
# Usage:
#   codex-imagegen.sh "<prompt>" "<target-path>"
#       Text-to-image: generate a new image from <prompt>.
#
#   codex-imagegen.sh "<prompt>" "<target-path>" <reference-image> [<reference-image> ...]
#       Image-edit: pass 1–16 reference images that codex's built-in image_gen tool
#       hands to gpt-image edit (composition, outfit-swap, scene-merge, style-transfer,
#       text-localization, ...). <prompt> describes the edit in plain English; for
#       composition the model reads "image 1 / image 2 / ..." by their order in the
#       arg list.
#
# Requires:
#   - `codex` CLI installed and authenticated (`codex login`)
#   - the user's Codex generated-images dir at $CODEX_HOME (default: ~/.codex)
#
# On success: prints the absolute path of the saved PNG.
# On failure: writes an error to stderr and exits non-zero.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  codex-imagegen.sh <prompt> <target-path>                       # text-to-image
  codex-imagegen.sh <prompt> <target-path> <ref> [<ref> ...]     # image-edit (1-16 refs)
USAGE
  exit 64
}

if [[ $# -lt 2 ]]; then usage; fi

PROMPT="$1"
TARGET="$2"
shift 2
REFS=("$@")

if (( ${#REFS[@]} > 16 )); then
  echo "ERROR: at most 16 reference images supported (got ${#REFS[@]})" >&2
  echo "        16 is gpt-image edit's documented hard cap; the API rejects more." >&2
  echo "        Note: 2-3 references still give the cleanest composition in practice." >&2
  exit 64
fi

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
mkdir -p "$(dirname "$TARGET")"

# Resolve + validate each reference to an absolute path. codex CLI's --image
# is variadic; passing absolute paths avoids cwd ambiguity inside the
# codex sandbox.
REF_ABS=()
for ref in "${REFS[@]}"; do
  if [[ ! -f "$ref" ]]; then
    echo "ERROR: reference image not found: $ref" >&2
    exit 1
  fi
  REF_ABS+=("$(realpath "$ref")")
done

if (( ${#REF_ABS[@]} == 0 )); then
  # Text-to-image (legacy 2-arg form, unchanged behaviour)
  OUT=$(codex exec -C "$(pwd)" -s workspace-write --skip-git-repo-check \
          "\$imagegen $PROMPT" 2>&1)
else
  # Image-edit. Build the canonical scaffolding that codex's image_gen tool
  # keys off (matches references/sample-prompts.md in
  # $CODEX_HOME/skills/.system/imagegen).
  INPUT_LINES=""
  i=1
  for abs in "${REF_ABS[@]}"; do
    INPUT_LINES+="Image $i: $abs"$'\n'
    i=$((i + 1))
  done

  if (( ${#REF_ABS[@]} == 1 )); then
    CONSTRAINT="Constraints: preserve the subject identity, framing, and geometry of the input image except where the request asks otherwise."
  else
    CONSTRAINT="Constraints: treat the input images as references the user is composing with — preserve identity and content from each image as the request implies (e.g. subject from Image 1, scene from Image 2)."
  fi

  EDIT_PROMPT="\$imagegen
Use case: image-edit
Input images:
${INPUT_LINES%$'\n'}
Primary request: $PROMPT
$CONSTRAINT"

  # --image is variadic in clap; `--` stops the positional prompt being
  # eaten as another image filename.
  IMAGE_FLAGS=()
  for abs in "${REF_ABS[@]}"; do
    IMAGE_FLAGS+=(--image "$abs")
  done

  OUT=$(codex exec -C "$(pwd)" -s workspace-write --skip-git-repo-check \
          "${IMAGE_FLAGS[@]}" -- "$EDIT_PROMPT" 2>&1)
fi

SID=$(printf '%s\n' "$OUT" | grep -oE 'session id: [a-f0-9-]+' | head -1 | awk '{print $3}')
if [[ -z "$SID" ]]; then
  echo "ERROR: failed to extract session id from codex output" >&2
  echo "--- codex output ---" >&2
  printf '%s\n' "$OUT" >&2
  exit 1
fi

# Codex's output location changed across versions:
#   - older: a PNG is written to $CODEX_HOME/generated_images/$SID/*.png
#   - 0.141+: the image is NOT written to disk; it's embedded as base64 in the
#     session rollout (the `result` field of the image_generation_end /
#     image_generation_call event). Try the on-disk PNG first, then fall back to
#     decoding the base64 out of the rollout .jsonl.
SRC_DIR="$CODEX_HOME/generated_images/$SID"
SRC=$(ls -t "$SRC_DIR"/*.png 2>/dev/null | head -1 || true)
if [[ -n "$SRC" ]]; then
  cp "$SRC" "$TARGET"
  realpath "$TARGET"
  exit 0
fi

# Fallback: decode the base64 PNG embedded in the session rollout (codex >= 0.141).
ROLLOUT=$(find "$CODEX_HOME/sessions" -type f -name "*$SID.jsonl" 2>/dev/null | head -1 || true)
if [[ -z "$ROLLOUT" ]]; then
  echo "ERROR: no PNG in $SRC_DIR and no rollout file for session $SID" >&2
  echo "(codex reported success but produced no retrievable image — try re-running)" >&2
  exit 1
fi

if python3 - "$ROLLOUT" "$TARGET" <<'PY'
import base64, json, sys
rollout, target = sys.argv[1], sys.argv[2]
b64 = None
with open(rollout, encoding="utf-8") as fh:
    for line in fh:
        if "iVBORw0KGgo" not in line:          # cheap pre-filter: PNG base64 magic
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        payload = obj.get("payload", {}) if isinstance(obj, dict) else {}
        if payload.get("type") in ("image_generation_end", "image_generation_call"):
            result = payload.get("result")
            if isinstance(result, str) and result:
                b64 = result                    # keep the last (newest) image
if not b64:
    sys.exit("no base64 image found in rollout")
with open(target, "wb") as out:
    out.write(base64.b64decode(b64))
PY
then
  realpath "$TARGET"
else
  echo "ERROR: codex produced no PNG file, and no decodable base64 image was found" >&2
  echo "       in the rollout: $ROLLOUT" >&2
  exit 1
fi
