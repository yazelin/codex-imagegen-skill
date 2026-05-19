---
name: codex-imagegen
description: Generate images via Codex CLI's $imagegen shorthand, using the user's ChatGPT subscription quota instead of OpenAI Images API credits. Use when the user wants to generate one or more PNG images from text prompts, has Codex CLI installed and logged in, and the use case is personal/local (not a production backend serving end users).
---

# codex-imagegen

Generate images by invoking Codex CLI's built-in `$imagegen` tool in non-interactive (`codex exec`) mode, then copying the resulting PNG out of Codex's default output directory to a path of your choice.

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
bash "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/codex-imagegen}/codex-imagegen.sh" "<prompt>" "<output-path>"
```

Or just resolve the script relative to where the skill was installed.

The script:

1. Runs `codex exec -C "$(pwd)" -s workspace-write --skip-git-repo-check '$imagegen <prompt>'`
2. Extracts the session id from Codex's stdout
3. Locates the generated PNG in `~/.codex/generated_images/<session-id>/`
4. Copies it to `<output-path>` and prints the absolute path

On success the script prints **one line** — the absolute path of the saved PNG. Use that path to read the image back, embed it, upload it, etc.

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
