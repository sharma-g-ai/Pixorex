"""Browser checks for the DN-scoped receiving wireframe, using an isolated Chrome."""
import asyncio
import base64
import json
from pathlib import Path

import requests
import websockets


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output' / 'qa'
ENDPOINT = 'http://127.0.0.1:9233'


class CDP:
    def __init__(self, ws):
        self.ws = ws
        self.serial = 0
        self.errors = []

    async def call(self, method, params=None):
        self.serial += 1
        ident = self.serial
        await self.ws.send(json.dumps({'id': ident, 'method': method, 'params': params or {}}))
        while True:
            message = json.loads(await self.ws.recv())
            if message.get('method') == 'Runtime.exceptionThrown':
                self.errors.append(message['params']['exceptionDetails'])
            if message.get('id') == ident:
                if 'error' in message:
                    raise RuntimeError(message['error'])
                return message.get('result', {})

    async def evaluate(self, expression):
        result = await self.call('Runtime.evaluate', {'expression': expression, 'returnByValue': True, 'awaitPromise': True})
        if 'exceptionDetails' in result:
            raise RuntimeError(result['exceptionDetails'])
        return result['result'].get('value')


async def main():
    tabs = requests.get(ENDPOINT + '/json/list', timeout=10).json()
    page_tab = next(t for t in tabs if t['type'] == 'page')
    async with websockets.connect(page_tab['webSocketDebuggerUrl'], max_size=30_000_000) as ws:
        page = CDP(ws)
        await page.evaluate('localStorage.clear()')
        await page.call('Page.reload', {'ignoreCache': True})
        await asyncio.sleep(1)
        tabs = requests.get(ENDPOINT + '/json/list', timeout=10).json()
        iframe_tab = next(t for t in tabs if t['type'] == 'iframe')
        async with websockets.connect(iframe_tab['webSocketDebuggerUrl'], max_size=30_000_000) as iframe_ws:
            frame = CDP(iframe_ws)
            await frame.call('Runtime.enable')
            result = await frame.evaluate(r"""(() => {
                const root = document.getElementById('seastock-receiving-wireframes');
                const q = selector => root.querySelector(selector);
                const checks = [];
                const check = (label, ok) => { if (!ok) throw Error(label); checks.push(label); };
                const click = selector => { const el = q(selector); if (!el || el.disabled) throw Error('Unavailable: ' + selector); el.click(); };
                const a = name => click('[data-action="' + name + '"], [data-stage="' + name + '"]');
                const session = () => window.openai.widgetState.privateContent.sessions.find(s => s.id === window.openai.widgetState.modelContent.selectedDn);
                const all = () => window.openai.widgetState.privateContent.sessions;
                const scan = (article, state = 'matched') => {
                    q('.ss-observed-article').value = article;
                    q('.ss-observation').value = state;
                    a('preview');
                };
                check('Landing shows actual four-page first DN', q('.ss-main').textContent.includes('4 pages'));
                click('[data-dn="5319364114"]');
                check('Document quantity 62, untouched physical total zero', session().rows.reduce((n,r) => n + r.expected,0) === 62 && session().rows.every(r => r.qty === 0));
                check('Physical count disabled before document finalisation', q('[data-stage="count"]').disabled);
                a('finalise');
                check('DN finalised before scanning', session().finalised === true);
                a('scan');
                check('Searching has disabled count acceptance', q('[data-action="accept"]').disabled);
                scan('445386', 'verifying');
                check('Candidate verification does not enable addition', q('[data-action="accept"]').disabled);
                scan('445386');
                check('Verified exact current-DN article enables Add this can', !q('[data-action="accept"]').disabled);
                check('Confirmed preview frames do not increment count', session().rows.every(r => r.qty === 0));
                const cachedButton = q('[data-action="accept"]');
                cachedButton.click(); cachedButton.click();
                check('Double tap adds exactly one can', session().rows.find(r => r.article === '445386').qty === 1);
                check('Accepted can requires Scan next can', !!q('[data-action="next"]') && !q('[data-action="accept"]'));
                scan('445386');
                check('Repeated frames after acceptance cannot rearm count', !q('[data-action="accept"]') && session().rows.find(r => r.article === '445386').qty === 1);
                a('undo');
                check('Undo reverses one accepted event', session().rows.find(r => r.article === '445386').qty === 0);
                a('accept'); a('next'); scan('445386'); a('accept');
                check('Two deliberate cans of the same article count twice', session().rows.find(r => r.article === '445386').qty === 2);
                a('next'); scan('445276');
                check('Article on another DN rejected for current DN', q('.ss-main').textContent.includes('Not on this DN') && q('[data-action="accept"]').disabled);
                const beforeNegative = session().rows.reduce((n,r) => n + r.qty,0);
                for (const state of ['blur', 'glare', 'hidden', 'conflict', 'verifying', 'searching']) {
                    scan('445386',state);
                    check(state + ' blocks acceptance', q('[data-action="accept"]').disabled);
                }
                for (const article of ['0000207630','8716242404767','UN1263','12/10/2026','0445386']) {
                    scan(article);
                    check('Distractor / unequal string rejected: ' + article, q('[data-action="accept"]').disabled);
                }
                scan('00464138'); a('unexpected');
                check('Unexpected attachment article has zero count delta', session().rows.reduce((n,r) => n + r.qty,0) === beforeNegative);
                check('Unexpected event retained and submission blocked', session().exceptions.length === 1 && q('[data-action="submit"]').disabled);
                a('resolve'); q('#ss-disposition').value = 'Can belongs to another delivery; set aside'; a('save-form');
                check('Disposition resolves exception without deleting history', session().exceptions[0].resolved && session().exceptions[0].article === '00464138');
                a('landing'); click('[data-dn="5319358250"]'); a('finalise'); a('scan'); scan('475210');
                check('Repeated article requires occurrence selection', q('.ss-allocation').children.length === 2 && q('[data-action="accept"]').disabled);
                click('[data-action="allocate"][data-id="5319358250:row:5"]'); a('accept');
                check('Repeated article increments selected page-four occurrence once', session().rows[5].qty === 1 && session().rows[3].qty === 0);
                a('landing'); click('[data-dn="5319364114"]');
                check('Switching DN retains separate totals', session().rows.find(r => r.article === '445386').qty === 2 && all().find(s => s.id === '5319358250').rows[5].qty === 1);
                const redRow = '[data-id="5319364114:row:5"]';
                click(redRow + '[data-action="finish"]');
                check('Short count requires variance reason', !!q('#ss-reason'));
                q('#ss-reason').value = 'Other'; a('save-form');
                check('Other variance requires details', q('.ss-error').textContent.includes('Explain'));
                q('#ss-details').value = 'Controlled partial receipt'; a('save-form');
                check('Finished short row is verified with reason', session().rows[5].status === 'verified' && session().rows[5].reason.includes('Controlled partial'));
                click(redRow + '[data-action="reopen"]');
                check('Reopen retains count and removes verification', session().rows[5].qty === 2 && session().rows[5].status === 'counting');
                a('document'); click(redRow + '[data-action="correct"]');
                q('#ss-expected').value = '9'; q('#ss-correction-reason').value = 'Verified paper correction'; a('save-form');
                check('Source correction preserves count and pauses scanning', session().rows[5].qty === 2 && !session().finalised && session().rows[5].status === 'recheck');
                check('Correction requires reviewed page before finalisation', q('[data-action="finalise"]').disabled);
                click('[data-action="check-page"][data-page="3"]');
                check('Printed Piece mismatch requires explicit source-summary review', q('[data-action="finalise"]').disabled && !!q('.ss-summary-review'));
                q('.ss-summary-review').checked = true; q('.ss-summary-review').dispatchEvent(new Event('change', {bubbles:true})); a('finalise');
                check('Re-finalisation resumes without resetting previous count', session().finalised && session().rows[5].qty === 2);
                a('landing'); click('[data-dn="LABEL-TEST"]'); a('finalise'); a('scan'); scan('00464138'); a('accept');
                check('Leading zeros retained on matched label-test article', session().rows.find(r => r.article === '00464138').qty === 1 && q('.ss-main').textContent.includes('00464138'));
                a('next'); scan('121186'); a('accept'); a('next'); scan('00121186'); a('accept');
                check('Six and eight digit article strings remain distinct', session().rows.find(r => r.article === '121186').qty === 1 && session().rows.find(r => r.article === '00121186').qty === 1);
                a('count');
                for (const row of structuredClone(session().rows)) {
                    if (row.qty === 0) {
                        click('[data-action="manual"][data-id="' + row.id + '"]');
                        q('#ss-quantity').value = '1'; q('#ss-manual-reason').value = 'Physical manual count'; a('save-form');
                    }
                    click('[data-action="finish"][data-id="' + row.id + '"]');
                }
                a('summary');
                check('Full row evidence allows submit only after finishing every row', !q('[data-action="submit"]').disabled && session().rows.every(r => r.status === 'verified'));
                check('Summary separates scanned and manual units', q('.ss-main').textContent.includes('3 scan-confirmed units') && q('.ss-main').textContent.includes('4 manually recorded units'));
                a('submit');
                check('Local submission locks row edits and scanning', session().submitted && q('[data-action="submit"]').disabled);
                a('count'); check('Submitted count list has no editable controls', !q('[data-action="manual"]') && !q('[data-action="scan"]') && !q('[data-action="row-scan"]'));
                const saved = structuredClone(window.openai.widgetState);
                saved.privateContent.writeId = 'reload-test';
                window.dispatchEvent(new CustomEvent('openai:set_globals', {detail:{globals:{widgetState:saved}}}));
                check('Restored state retains submitted counts and leading zeros', q('.ss-main').textContent.includes('00464138') && q('.ss-main').textContent.includes('7 / 7 PC'));
                check('Saved interaction state remains below 16 KiB', new TextEncoder().encode(JSON.stringify(window.openai.widgetState)).length < 16384);
                a('landing'); click('[data-dn="5319364114"]'); a('scan'); scan('445386');
                return checks;
            })()""")
            layouts = []
            for width in [320, 736]:
                await page.call('Emulation.setDeviceMetricsOverride', {'width': width, 'height': 1250, 'deviceScaleFactor': 1, 'mobile': False})
                for state in ['scan', 'summary', 'document', 'count', 'landing']:
                    if state != 'scan':
                        await frame.evaluate(f"document.querySelector('#seastock-receiving-wireframes [data-action=\"{state}\"], #seastock-receiving-wireframes [data-stage=\"{state}\"]')?.click()")
                    await frame.evaluate('new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))')
                    layout = await frame.evaluate("""(() => ({ width:document.documentElement.clientWidth, scrollWidth:document.documentElement.scrollWidth,
                        overflow:[...document.querySelectorAll('#seastock-receiving-wireframes button,#seastock-receiving-wireframes input,#seastock-receiving-wireframes select')].filter(e=>e.getBoundingClientRect().width>0 && e.scrollWidth>e.clientWidth+3).map(e=>e.textContent.trim()) }))()""")
                    if layout['scrollWidth'] > layout['width'] or layout['overflow']:
                        raise AssertionError((width, state, layout))
                    layouts.append({'viewport': width, 'state': state, **layout})
                    shot = await page.call('Page.captureScreenshot', {'format': 'png', 'captureBeyondViewport': True})
                    (OUT / f'seastock-{state}-{width}.png').write_bytes(base64.b64decode(shot['data']))
                # Restore scanner for the next viewport check.
                await frame.evaluate("document.querySelector('[data-dn=\"5319364114\"]').click(); document.querySelector('[data-action=\"scan\"]').click(); document.querySelector('.ss-observed-article').value='445386'; document.querySelector('[data-action=\"preview\"]').click();")
            report = {'functional_checks': result, 'layouts': layouts, 'runtime_errors': frame.errors + page.errors}
            (OUT / 'seastock-wireframe-checks.json').write_text(json.dumps(report, indent=2))
            print(json.dumps({'functional_checks_passed': len(result), 'responsive_states_passed': len(layouts), 'runtime_errors': report['runtime_errors']}))
            if report['runtime_errors']:
                raise AssertionError(report['runtime_errors'])


asyncio.run(main())
