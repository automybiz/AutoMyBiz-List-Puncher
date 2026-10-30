# prompts/

The AI prompts the app copies to the clipboard, kept as Markdown so they can be read, reviewed and
diffed properly instead of living inside a template literal in `index.html`.

| File | What it holds |
|---|---|
| `ai-prompt-user.md` | **HEAD** of the user prompt - the one-off ask ("convert the discussion above"). |
| `ai-prompt-system.md` | **HEAD** of the system prompt - the role and the standing-instructions framing. |
| `ai-prompt-shared.md` | **BODY** both prompts end with - the format rules and the list structure. |

Every file shares the `ai-prompt-` prefix, so they sort next to each other.

## How the sharing works

Both prompts are composed as **HEAD + blank line + BODY**. Only the opening differs, so:

- change a format rule -> edit `ai-prompt-shared.md`, and both prompts change together;
- change the tone of the user prompt -> edit `ai-prompt-user.md`, and the system prompt is untouched.

Nothing is duplicated, so a rule can never drift out of sync between the two versions.

## After editing

```bash
node tools/sync-ai-prompts.mjs          # rewrite the block in index.html
node tools/sync-ai-prompts.mjs --check  # exit 1 if index.html is out of date (use before committing)
```

Commit the `.md` file **and** the regenerated `index.html` in the same commit.

## Why the text is embedded instead of fetched

`fetch('prompts/ai-prompt-user.md')` would work on GitHub Pages, but the app is routinely opened
straight off disk (`file://`), where every current browser blocks reading a sibling file - the Copy
buttons would silently stop working in the normal dev workflow. GitHub Pages also caches assets for
about 10 minutes. So `tools/sync-ai-prompts.mjs` copies the text into `index.html` at authoring time
and the shipped product stays exactly two files, with no network call and no build step.

`index.html` between the `// >>> AI-PROMPT-LIBRARY` and `// <<< AI-PROMPT-LIBRARY` markers is
generated - edit the `.md` files, not that block.
