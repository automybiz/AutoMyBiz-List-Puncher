const { spawn } = require('child_process');
const path = require('path');

const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const port = 9333;
const url = 'file:///X:/DATA/_SOFTWARE/_3D_PRINTING/_PROJECTS/_WEB/CODE/AutoMyBiz%20List%20Puncher/.tmp-test-render.html';

const chrome = spawn(chromePath, [
    '--headless=new',
    '--disable-gpu',
    '--no-sandbox',
    '--disable-dev-shm-usage',
    '--no-first-run',
    '--remote-debugging-port=' + port,
    '--user-data-dir=' + path.resolve('.tmp-cdp-profile'),
    '--allow-file-access-from-files',
    url
], { stdio: 'ignore' });

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function getTargets() {
    for (let i = 0; i < 30; i++) {
        try {
            const res = await fetch(`http://127.0.0.1:${port}/json/list`);
            const list = await res.json();
            if (list && list.length) return list;
        } catch (e) { /* not up yet */ }
        await sleep(500);
    }
    throw new Error('Chrome DevTools endpoint did not start');
}

(async () => {
    try {
        const targets = await getTargets();
        const page = targets.find(t => t.type === 'page' && t.url.includes('.tmp-test-render')) || targets.find(t => t.type === 'page');
        if (!page) throw new Error('No page target');

        const ws = new WebSocket(page.webSocketDebuggerUrl);
        await new Promise((resolve, reject) => {
            ws.onopen = resolve;
            ws.onerror = reject;
        });

        const expression = `JSON.stringify({
            whiteSpace: getComputedStyle(document.getElementById('notes')).whiteSpace,
            tabSize: getComputedStyle(document.getElementById('notes')).tabSize,
            renderedText: document.getElementById('notes').innerText
        })`;

        const result = await new Promise((resolve, reject) => {
            ws.onmessage = event => {
                const msg = JSON.parse(event.data);
                if (msg.id === 1) resolve(msg);
            };
            ws.onerror = reject;
            ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression, returnByValue: true } }));
        });

        const value = result.result.result.value;
        const parsed = JSON.parse(value);
        console.log('computed white-space:', parsed.whiteSpace);
        console.log('computed tab-size:', parsed.tabSize);
        console.log('rendered innerText:');
        console.log(parsed.renderedText);
        const ok = parsed.whiteSpace === 'pre-wrap'
            && parsed.renderedText.includes('\n  "accessType"')
            && parsed.renderedText.includes('\n    "partner"')
            && parsed.renderedText.includes('\n      "id"');
        console.log(ok ? 'PASS - browser renders preserved indentation' : 'FAIL - indentation not preserved');
        ws.close();
        chrome.kill();
        process.exit(ok ? 0 : 1);
    } catch (err) {
        console.error('ERROR:', err.message);
        chrome.kill();
        process.exit(2);
    }
})();
