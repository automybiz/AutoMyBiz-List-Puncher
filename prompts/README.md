# prompts/

The AI prompt text the two Copy buttons put on the clipboard. **This folder holds the only copy of
it** - `index.html` contains none of it.

| File | Holds |
|---|---|
| `ai-prompt-shared.js` | **BODY** both prompts end with - the format rules and the list structure |
| `ai-prompt-system.js` | **HEAD** used only by the system prompt - the role and the standing instructions |
| `ai-prompt-user.js` | **HEAD** only the user prompt uses - the one-off ask |

Every file shares the `ai-prompt-` prefix, so they sort next to each other.

## How the two versions share text

Copied text = **HEAD + blank line + BODY**. Only the opening differs, so:

- change a format rule -> edit `ai-prompt-shared.js`, and both prompts change together;
- change the tone of the user prompt -> edit `ai-prompt-user.js`, and the system prompt is untouched.

Nothing is duplicated anywhere, so a rule cannot drift between the two versions, and `index.html`
contains no prompt text at all.

## Why `.js` and not `.md`

`index.html` loads these files with plain `<script src="...">` tags. That is the only way one copy of
the text can load everywhere this app runs:

| | `<script src>` | `fetch('*.md')` |
|---|---|---|
| GitHub Pages / the GHL menu link | works | works only with a `.nojekyll` file - Jekyll otherwise converts `.md` into `.html` |
| `index.html` opened off disk (`file://`) | works | **blocked** by every browser (CORS), so the Copy buttons would die |

## Editing

Open the file, change the text inside the backticks, save, reload. There is no build step and no
second copy to keep in sync.

Two rules, because the text sits inside a JS template literal:

- no bare backticks and no `${` in the prompt text (escape them, or reword);
- run `node --check prompts/ai-prompt-*.js` after editing.

