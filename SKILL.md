---
name: codex-imagegen
description: Generate or edit images via Codex CLI's $imagegen shorthand, using the user's ChatGPT subscription quota instead of OpenAI Images API credits. Supports pure text-to-image AND multi-image edit (composition, outfit-swap, scene-merge, style-transfer) with 1–4 reference images. Use when the user wants to generate or transform PNG images, has Codex CLI installed and logged in, and the use case is personal/local (not a production backend serving end users).
---

# codex-imagegen

Generate or edit images by invoking Codex CLI's built-in `$imagegen` tool in non-interactive (`codex exec`) mode, then copying the resulting PNG out of Codex's default output directory to a path of your choice.

Two modes:

- **Text-to-image** (default, 2-arg form): generate a brand-new image from a text prompt.
- **Image-edit** (3+ arg form): pass 1–4 reference images so `gpt-image` can do composition, outfit-swap, scene-merge, style-transfer, text-localization, etc. The script builds the canonical `Use case: image-edit` / `Input images: Image 1 / Image 2 / ...` prompt scaffolding the built-in `image_gen` tool keys off.

## When this skill applies

Use this skill when **all** of the following hold:

- The user has Codex CLI installed (`codex --version` works) and is logged in (`codex login` done at least once).
- The use case is **personal / local / dev-time**: writing a blog cover, mocking up an icon, generating reference art, batch-filling missing images on a personal site.
- Cost matters: the user wants to use their existing ChatGPT subscription quota rather than pay per-image via OpenAI Images API.

Do **NOT** use this skill when:

- The user is building a production backend that serves end users (LINE bots, web apps, etc.). ChatGPT subscriptions are for personal use; programmatic per-user image generation should use the OpenAI Images API with a proper API key.
- Codex CLI is not installed. Fall back to other image-generation skills (e.g. `nanobanana`) or ask the user to install Codex first.

## How to invoke

The skill ships with `codex-imagegen.sh`. Run it from the directory containing this `SKILL.md`:

```bash
# Text-to-image
bash "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/codex-imagegen}/codex-imagegen.sh" \
  "<prompt>" "<output-path>"

# Image-edit (1–4 reference images)
bash "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/codex-imagegen}/codex-imagegen.sh" \
  "<edit prompt>" "<output-path>" "<ref1.png>" "<ref2.png>" ...
```

Or just resolve the script relative to where the skill was installed.

The script:

1. Validates reference image paths exist (if any) and resolves them to absolute paths.
2. Runs `codex exec -C "$(pwd)" -s workspace-write --skip-git-repo-check [--image P]... [--] '$imagegen <built prompt>'`. In edit mode, each `--image` flag carries one reference; the `--` separator stops the positional prompt being parsed as another image. The built prompt follows the canonical scaffolding (`Use case: image-edit`, `Input images: Image 1: …`, `Primary request: …`, `Constraints: …`).
3. Extracts the session id from Codex's stdout.
4. Locates the generated PNG in `~/.codex/generated_images/<session-id>/`.
5. Copies it to `<output-path>` and prints the absolute path.

On success the script prints **one line** — the absolute path of the saved PNG.

### Writing edit prompts

For multi-image edits the prompt should reference inputs by their position in the arg list (`image 1`, `image 2`, …). Examples:

| Use case | Prompt template |
|---|---|
| composition | "place the subject from image 1 into the scene from image 2; match lighting and perspective" |
| outfit-swap | "replace only the clothing on image 1 with the garments from image 2 and image 3; preserve face, body shape, and pose" |
| style-transfer | "apply the visual style of image 1 to the subject in image 2; preserve composition of image 2" |
| text-localization | "translate every text element in image 1 to Japanese; preserve typography, layout, and spacing" |
| sketch-to-render | "turn the line drawing in image 1 into a photorealistic render; preserve layout and proportions" |

The script enforces a 4-image cap. `gpt-image` accepts more, but in practice 2–3 references gives the cleanest composition; bump the cap in the script if you have a real need.

## Prompt craft

OpenAI's image model responds well to detailed visual descriptions. A good prompt includes:

- **Subject / composition**: what objects, where they sit, how they relate ("a chat bubble on the left connected by curved arrows to three tarot cards on the right")
- **Style**: flat illustration / photorealistic / watercolor / 3D clay-render / line art / etc.
- **Color palette**: specific colors, named or descriptive ("soft pastels — periwinkle, sage, coral")
- **Background**: ("very light pastel gradient, cream to pale blue")
- **Aspect ratio guidance**: ("wide landscape, approximately 2:1")
- **Mood / lighting**: ("calm, warm, welcoming", "dramatic backlight")
- **Negative constraints**: ("no text, no letters, no watermark, no human figures, no logos")

When generating a **series** of images that should share a style, draft a reusable style block once and append it to every per-image concept prompt. The bundled `codex-imagegen.sh` does not impose any style — you control the entire prompt.

## Batching

For batch jobs (e.g. blog cover backfill), don't call this script in a `while read < manifest` loop directly — `codex exec` reads from stdin and will consume the rest of the manifest. Redirect: `./codex-imagegen.sh ... </dev/null`. The included script handles its own stdin; the caller is responsible for not piping the manifest into it.

Each image takes ~40-70 seconds on the OpenAI side. A batch of 26 images takes roughly 22 minutes.

## Known issues

- **Linux bubblewrap sandbox in nested environments**: Codex's own sandbox can fail (`bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`) when trying to do post-generation shell work like `cp`. This is why the bundled script does the copy itself, outside Codex's sandbox.
- **Image is saved to a Codex-managed dir first**: `~/.codex/generated_images/<session>/ig_*.png`. The script handles this for you.

## Quota & policy

This skill uses the user's ChatGPT subscription. Image generation counts against that subscription's quota, not against any OpenAI API credit. Do not use this skill to power production multi-user services — that violates the spirit of the subscription terms.
