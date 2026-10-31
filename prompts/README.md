# prompts/

The AI prompt text the two Copy buttons put on the clipboard. **This folder holds the only copy of
it** - `index.html` contains none of it.

| File | Holds |
|---|---|
| `ai-prompt-shared.md` | **BODY** both prompts end with - the format rules and the list structure |
| `ai-prompt-system.md` | **HEAD** used only by the system prompt - the role and the standing instructions |
| `ai-prompt-user.md` | **HEAD** only the user prompt uses - the one-off ask |

Every file shares the `ai-prompt-` prefix, so they sort next to each other.

## How the two versions share text

Copied text = **HEAD + blank line + BODY**. Only the opening differs, so:

- change a format rule -> edit `ai-prompt-shared.md`, and both prompts change together;
- change the tone of the user prompt -> edit `ai-prompt-user.md`, and the system prompt is untouched.

Nothing is duplicated anywhere, so a rule cannot drift between the two versions, and `index.html`
contains no prompt text at all.

## Editing

Plain Markdown, nothing to escape: real ``` fences, quotes, `$`, apostrophes and all. Edit the file,
save, reload the page, click the button. There is no build step and no second copy to keep in sync.

## It needs http(s)

The app fetches these files at runtime:

```js
fetch('prompts/ai-prompt-user.md?v=' + APP_BUILD)
```

- **GitHub Pages / the GHL menu link:** works. Pages serves `.md` as `text/markdown` (measured:
  `docs/HANDOVER.md` and `docs/SETUP-SUPABASE-MCP.md` both return `200 text/markdown`), so no
  `.nojekyll` file is needed.
- **`index.html` opened straight off disk (`file://`):** the browser refuses to fetch a sibling file
  (CORS, origin `null`), so both buttons toast *"Copy AI Prompt needs http(s)"* instead of copying.
  Everything else in the app still works.

`.md` was chosen over `.js` deliberately: a `.js` file has to be loaded by a script tag (which would
work off disk) but then the prompt sits inside a template literal, so every ``` has to be written as
`\`\`\`` and every `${` escaped. Markdown keeps the text exactly as a human would write it.

**Working on a prompt locally?** Serve the folder instead of opening the file:

```bash
python -m http.server 8765     # then open http://127.0.0.1:8765/index.html
```

That reads your working copy (no commit, no push) and copies correctly.


