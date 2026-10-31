// Validates a List Puncher list file against the app's OWN parser, extracted
// straight out of index.html, so a guide cannot drift away from what the app reads.
//
// Usage:  node tools/validate-list-format.mjs docs/HOWTO-VSCODE-SETTINGS.md
//
// Node is only needed for this check. The app itself has no build step.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');

const target = process.argv[2];
if (!target) {
    console.error('usage: node tools/validate-list-format.mjs <list-file>');
    process.exit(2);
}

const appHtml = readFileSync(join(root, 'index.html'), 'utf8');
const appLines = appHtml.split(/\r?\n/);

const at = (from, to, label) => {
    const slice = appLines.slice(from - 1, to);
    if (!slice.length) throw new Error(`could not slice ${label}`);
    return slice.join('\n');
};

// 1. Constants block (TASK_*, MARK_*, FORMAT_STAMP, INDENT_SPACES_PER_LEVEL).
const constStart = appLines.findIndex(l => l.includes('const TASK_BLANK')) + 1;
if (!constStart) throw new Error('TASK_BLANK not found in index.html');
const constEnd = appLines.findIndex((l, i) => i + 1 > constStart && /const FORMAT_STAMP/.test(l)) + 1;
const indentLine = appLines.find(l => /^\s*const INDENT_SPACES_PER_LEVEL\s*=/.test(l));
if (!indentLine) throw new Error('INDENT_SPACES_PER_LEVEL not found in index.html');
const constants = [indentLine.trim(), at(constStart, constEnd, 'constants')].join('\n');

// 2. Small top-level helpers the parser calls: slice from the "function" line to
//    the line before the next top-level function declaration.
function fnBlock(name) {
    const re = new RegExp('^\\s{0,8}function\\s+' + name + '\\s*\\(');
    const start = appLines.findIndex(l => re.test(l));
    if (start < 0) throw new Error(`${name} not found in index.html`);
    const nextIdx = appLines.findIndex((l, i) => i > start && /^\s{0,8}function\s+\w+\s*\(/.test(l));
    let last = (nextIdx === -1 ? appLines.length : nextIdx) - 1;
    while (last > start && appLines[last].trim() === '') last--;
    return appLines.slice(start, last + 1).join('\n');
}

const slugSrc = fnBlock('generateSlugId');
const markerSrc = fnBlock('markerToState');

// 3. The parser engine: from the banner above quoteScalar to the banner that
//    follows parseLegacyShorthand. Everything the readers need lives in between.
const ENGINE_BANNER = 'LIST FORMAT PARSER & SERIALIZER ENGINE';
const bannerIdx = appLines.findIndex(l => l.includes(ENGINE_BANNER));
if (bannerIdx < 1) throw new Error('parser engine banner not found in index.html');
const engineStart0 = bannerIdx - 1; // include the "# ====" rule line above it

const legacyIdx = appLines.findIndex(l => /function parseLegacyShorthand\s*\(/.test(l));
if (legacyIdx < 0) throw new Error('parseLegacyShorthand not found in index.html');
const engineEnd0 = appLines.findIndex((l, i) => i > legacyIdx && /^\s*\/\/ ={10,}\s*$/.test(l));
if (engineEnd0 < 0) throw new Error('could not find the end of the parser engine');

const engine = appLines.slice(engineStart0, engineEnd0).join('\n');

const program = [
    constants,
    slugSrc,
    markerSrc,
    engine,
    'return { parseChecklistText, TASK_YES, TASK_NO, TASK_BLANK, MARK_YES, MARK_NO, FORMAT_STAMP };'
].join('\n\n');

let api;
try {
    api = new Function(program)();
} catch (err) {
    console.error('FATAL: could not load the parser out of index.html');
    console.error(err.message);
    process.exit(3);
}

const text = readFileSync(join(root, target), 'utf8');

const problems = [];
if (!text.startsWith(api.FORMAT_STAMP)) problems.push(`missing format stamp on line 1 (${api.FORMAT_STAMP})`);
if (/\t/.test(text)) problems.push('contains a tab character - indentation must be spaces');

const rows = api.parseChecklistText(text);
const sections = rows.filter(r => r.level === 0);
const tasks = rows.filter(r => r.level > 0);

if (!sections.length) problems.push('no section: block was recognised');
if (!tasks.length) problems.push('no tasks were recognised');

const titled = tasks.filter(t => t.title && t.title.trim());
if (titled.length !== tasks.length) problems.push(`${tasks.length - titled.length} task(s) parsed with an empty title`);

const states = { blank: 0, yes: 0, no: 0 };
titled.forEach(t => {
    const s = t.state || api.TASK_BLANK;
    states[s] = (states[s] || 0) + 1;
});

const withNotes = titled.filter(t => t.notes && t.notes.trim());
const noteHead = withNotes.slice(0, 3).map(t => `  - ${t.title.slice(0, 46)} -> "${String(t.notes).split('\n')[0].slice(0, 52)}"`);

const numbers = titled.map(t => t.level);
const maxLevel = numbers.length ? Math.max(...numbers) : 0;

const levelCounts = {};
numbers.forEach(n => { levelCounts[n] = (levelCounts[n] || 0) + 1; });
const indentCounts = { 2: 0, 4: 0, 6: 0, 8: 0, deeper: 0 };
text.split(/\r?\n/).forEach(line => {
    const m = line.match(/^( *)- \[/);
    if (!m) return;
    const n = m[1].length;
    if (n <= 8) indentCounts[n] = (indentCounts[n] || 0) + 1;
    else indentCounts.deeper++;
});
const expectedTop = indentCounts[2] || 0;
const parsedTop = levelCounts[1] || 0;
if (expectedTop !== parsedTop) {
    problems.push(`indent says ${expectedTop} top-level task(s) but the parser produced ${parsedTop} at level 1`);
}

console.log(`file        : ${target}`);
console.log(`sections    : ${sections.length}`);
console.log(`tasks       : ${tasks.length}  (max nesting level ${maxLevel})`);
console.log(`per level   : ${Object.keys(levelCounts).sort().map(l => `L${l}=${levelCounts[l]}`).join('  ')}`);
console.log(`states      : [ ] ${states.blank}   [v] ${states.yes}   [x] ${states.no}`);
console.log(`with notes  : ${withNotes.length}`);
console.log(`section [1] : ${sections[0] ? sections[0].title : '(none)'}`);
console.log(`section [n] : ${sections[sections.length - 1] ? sections[sections.length - 1].title : '(none)'}`);
noteHead.forEach(l => console.log(`note sample :${l.slice(1)}`));

if (problems.length) {
    console.log('');
    problems.forEach(p => console.log('PROBLEM: ' + p));
    process.exit(1);
}

console.log('');
console.log('OK: the app\'s own parser reads this file cleanly.');
