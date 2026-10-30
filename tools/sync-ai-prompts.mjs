// Composes the List Puncher AI prompts out of prompts/*.md and re-embeds them
// into index.html, so the prompt text lives in a readable Markdown file instead
// of a template literal nobody wants to edit inside the app.
//
// Usage:
//   node tools/sync-ai-prompts.mjs            rewrite the block in index.html
//   node tools/sync-ai-prompts.mjs --check    exit 1 if index.html is out of date
//
// Why a sync step instead of fetch() at runtime: the app is routinely opened
// straight off disk (file://), where fetching a sibling file is blocked by every
// current browser, and GitHub Pages caches assets for ~10 minutes. Embedding the
// text keeps the shipped product at index.html + index.css, with no network call
// and no build step - this script only copies TEXT into the page.

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const checkOnly = process.argv.includes('--check');

const INDEX = join(root, 'index.html');
const PROMPT_DIR = join(root, 'prompts');

// HEAD + BODY: ai-prompt-user.md / ai-prompt-system.md hold only the opening
// that differs between the two, ai-prompt-shared.md holds the rules both obey.
// That way a change to the format rules is a one-file diff in git.
const FRAGMENTS = [
    { constName: 'AI_PROMPT_USER', file: 'ai-prompt-user.md', role: 'user head' },
    { constName: 'AI_PROMPT_SYSTEM', file: 'ai-prompt-system.md', role: 'system head' },
    { constName: 'AI_PROMPT_SHARED', file: 'ai-prompt-shared.md', role: 'shared body' }
];

const START_MARKER = '// >>> AI-PROMPT-LIBRARY';
const END_MARKER = '// <<< AI-PROMPT-LIBRARY';

function die(message, code) {
    console.error(`ERROR: ${message}`);
    process.exit(code);
}

function readFragment(fragment) {
    let raw;
    try {
        raw = readFileSync(join(PROMPT_DIR, fragment.file), 'utf8');
    } catch (err) {
        die(`could not read prompts/${fragment.file} (${err.code || err.message})`, 2);
    }
    // Normalise to LF, then trim - the file's own trailing newline is not part
    // of the prompt, otherwise every copy would end with a blank line or two.
    const text = raw.replace(/\r\n/g, '\n').replace(/^\uFEFF/, '').trim();
    if (!text) die(`prompts/${fragment.file} is empty`, 2);
    // A literal </script> inside a template literal ends the inline script block,
    // no matter how deeply it is escaped. Catch it here rather than in the browser.
    if (/<\/script/i.test(text)) {
        die(`prompts/${fragment.file} contains "</script", which would terminate the inline script block`, 2);
    }
    return text;
}

// Escape for a single-quoted-delimiter template literal. The backslash must go
// first, then backticks, then ${ (which would otherwise interpolate).
function toTemplateLiteral(text) {
    return text
        .replace(/\\/g, '\\\\')
        .replace(/`/g, '\\`')
        .replace(/\$\{/g, '\\${');
}

const html = readFileSync(INDEX, 'utf8');
const eol = html.includes('\r\n') ? '\r\n' : '\n';

const fragments = FRAGMENTS.map(fragment => {
    const text = readFragment(fragment);
    return { ...fragment, text: toTemplateLiteral(text), chars: text.length, lines: text.split('\n').length };
});

const startAt = html.indexOf(START_MARKER);
const endAt = html.indexOf(END_MARKER);
if (startAt < 0 || endAt < 0) die(`the ${START_MARKER} / ${END_MARKER} markers are missing from index.html`, 3);
if (endAt < startAt) die('the AI-PROMPT-LIBRARY end marker sits above its start marker', 3);

// The generated region is everything BETWEEN the two marker lines; the markers
// themselves stay hand-written so this script cannot mangle them.
const bodyStart = html.indexOf('\n', startAt) + 1;
const endLineStart = html.lastIndexOf('\n', endAt) + 1;
const currentBody = html.slice(bodyStart, endLineStart);

// Emit one const per fragment. The prompt's own line breaks are rewritten to the
// file's line endings so the generated block never mixes LF into a CRLF file -
// that keeps `--check` honest after a fresh clone, whatever git decided to check
// out. buildAiPrompt() in index.html normalises back to LF at copy time.
const generatedBody = fragments
    .map(fragment => `    const ${fragment.constName} = \`${fragment.text.split('\n').join(eol)}\`;`)
    .join(eol + eol) + eol;

fragments.forEach(fragment => {
    console.log(`${fragment.file.padEnd(22)} ${String(fragment.chars).padStart(6)} chars  ${String(fragment.lines).padStart(4)} lines  -> ${fragment.constName}`);
});

if (currentBody === generatedBody) {
    console.log('');
    console.log('OK: index.html already matches prompts/*.md.');
    process.exit(0);
}

if (checkOnly) {
    console.log('');
    console.log('STALE: index.html does not match prompts/*.md. Run: node tools/sync-ai-prompts.mjs');
    process.exit(1);
}

writeFileSync(INDEX, html.slice(0, bodyStart) + generatedBody + html.slice(endLineStart), 'utf8');
console.log('');
console.log('WROTE: index.html AI-PROMPT-LIBRARY block regenerated.');
