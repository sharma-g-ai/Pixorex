(() => {
  const root = document.getElementById('seastock-receiving-wireframes');
  const app = root.querySelector('.ss-app');
  const header = root.querySelector('.ss-header');
  const nav = root.querySelector('.ss-stages');
  const main = root.querySelector('.ss-main');
  const footer = root.querySelector('.ss-footer');
  const overlay = root.querySelector('.ss-overlay');
  const notice = root.querySelector('.ss-announcement');
  const preview = root.querySelector('.ss-preview-controls');
  const designs = { spacing: 'Comfortable', diagnostics: false };
  const data = [
    { id: '5319364114', pages: 4, piece: 62, label: 'Source DN fixture', rows: [
      ['445235', 15, 2, 'S COVER 456 BAS GREY'], ['445182', 15, 2, 'S COVER 256/435/456/522 HRD'],
      ['475212', 7, 3, 'S PRIME 200 BAS YEL/GREEN'], ['475210', 7, 3, 'S PRIME 200 HRD'],
      ['445377', 2, 3, 'S RINE 48 GREEN'], ['445386', 8, 3, 'S RINE 48 RED'], ['445374', 8, 4, 'S RINE 48 BLUE']
    ] },
    { id: '5319358250', pages: 6, piece: 100, label: 'Source DN fixture', rows: [
      ['445276', 4, 2, 'S DUR 550 BAS GREY'], ['445254', 4, 2, 'S DUR 520/550 HRD'],
      ['475211', 15, 3, 'S PRIME 200 BAS GREY'], ['475210', 15, 3, 'S PRIME 200 HRD'],
      ['475212', 5, 3, 'S PRIME 200 BAS YEL/GREEN'], ['475210', 5, 4, 'S PRIME 200 HRD'],
      ['445332', 1, 4, 'S GUARD CSF 585 BAS BLUE'], ['468181', 1, 4, 'S GUARD CSF 585 HRD'],
      ['445450', 3, 5, 'THINNER 21-06'], ['445458', 3, 5, 'THINNER 91-92'],
      ['445365', 4, 5, 'S RINE 28 REDBROWN'], ['445382', 16, 6, 'S RINE 48 GREY'],
      ['445378', 16, 6, 'S RINE 48 GREEN'], ['445430', 8, 6, 'S THERM 500']
    ] },
    { id: 'LABEL-TEST', pages: 1, piece: 7, label: 'Illustrative label-test DN', rows: [
      ['00240476', 1, 1, 'SIGMADUR 550 · BASE'], ['121186', 1, 1, 'SIGMADUR 550 · BASE'],
      ['00464138', 1, 1, 'SIGMACOVER 350 · BASE'], ['00220294', 1, 1, 'SIGMACOVER 350 · HARDENER'],
      ['30082418', 1, 1, 'SIGMATHERM 350 · ONE COMPONENT'], ['00121186', 1, 1, 'THINNER 91-92'],
      ['30013603', 1, 1, 'SIGMARINE ONE 648 · ONE COMPONENT']
    ] }
  ];
  const makeSessions = () => data.map(dn => ({ id: dn.id, finalised: false, revision: 1, summaryReviewed: false,
    checked: Array.from({ length: dn.pages }, (_, i) => i + 1), submitted: false,
    rows: dn.rows.map((row, i) => ({ id: `${dn.id}:row:${i}`, article: row[0], expected: row[1], page: row[2], product: row[3], qty: 0, scanned: 0, manual: 0, status: 'untouched', reason: '' })),
    events: [], exceptions: []
  }));
  let sessions = makeSessions();
  let selected = data[0].id;
  let stage = 'landing';
  let search = '';
  let filter = 'all';
  let scan = { state: 'searching', article: '', target: null, accepted: false };
  let returnFocus = null;
  let serial = 0;
  let lastWriteId = null;
  const safe = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
  const current = () => sessions.find(s => s.id === selected);
  const fixture = () => data.find(d => d.id === selected);
  const total = (s, key) => s.rows.reduce((n, row) => n + row[key], 0);
  const verified = s => s.rows.filter(row => row.status === 'verified').length;
  const pending = s => s.exceptions.filter(e => !e.resolved).length;
  const summaryMismatch = s => total(s, 'expected') !== data.find(d => d.id === s.id).piece;
  const sourceReady = s => s.checked.length === data.find(d => d.id === s.id).pages && (!summaryMismatch(s) || s.summaryReviewed);
  const ready = s => s.finalised && sourceReady(s) && verified(s) === s.rows.length && s.rows.every(r => r.qty === r.expected || r.reason.trim()) && !pending(s);
  const statusLabel = row => ({ untouched: 'Not started', counting: 'Counting', recheck: 'Recheck count', verified: 'Verified' })[row.status];
  const signed = n => n > 0 ? '+' + n : String(n);
  const rowById = id => current().rows.find(row => row.id === id);
  const matchRows = article => current().rows.filter(row => row.article === article);
  const button = (action, label, primary = false, disabled = false, extra = '') => `<button type="button" data-action="${action}" class="${primary ? 'ss-primary ' : ''}cursor-interaction" ${disabled ? 'disabled' : ''} ${extra}>${label}</button>`;
  const announce = text => { notice.textContent = text; };
  function save() {
    if (!window.openai || typeof window.openai.setWidgetState !== 'function') return;
    lastWriteId = `${Date.now()}:${++serial}`;
    const state = { modelContent: { workflow: 'dn-scoped-can-count-v1', selectedDn: selected,
      deliveries: sessions.map(s => ({ dn: s.id, finalised: s.finalised, accepted: total(s, 'qty'), expected: total(s, 'expected'), verifiedRows: verified(s), unexpected: pending(s), submitted: s.submitted })) },
      privateContent: { sessions: sessions.map(s => ({ ...s, events: s.events.slice(-4) })), stage, search, filter, writeId: lastWriteId } };
    window.openai.setWidgetState(state).catch(() => {});
  }
  function restore(snapshot) {
    const saved = snapshot?.privateContent;
    if (snapshot?.modelContent?.workflow !== 'dn-scoped-can-count-v1' || !saved || !Array.isArray(saved.sessions) || saved.sessions.length !== data.length) return;
    const baseline = makeSessions();
    if (!saved.sessions.every((s, i) => s.id === baseline[i].id && typeof s.finalised === 'boolean' && typeof s.submitted === 'boolean' && Array.isArray(s.checked) && new Set(s.checked).size === s.checked.length && s.checked.every(p => Number.isInteger(p) && p >= 1 && p <= data[i].pages) && Array.isArray(s.rows) && s.rows.length === baseline[i].rows.length && s.rows.every((row, j) => row.id === baseline[i].rows[j].id && row.article === baseline[i].rows[j].article && Number.isSafeInteger(row.expected) && row.expected >= 0 && Number.isSafeInteger(row.qty) && row.qty >= 0 && Number.isSafeInteger(row.scanned) && row.scanned >= 0 && Number.isSafeInteger(row.manual) && row.manual >= 0 && row.qty === row.scanned + row.manual && ['untouched', 'counting', 'recheck', 'verified'].includes(row.status) && typeof row.reason === 'string') && Array.isArray(s.events) && Array.isArray(s.exceptions) && s.exceptions.every(e => typeof e.article === 'string' && typeof e.resolved === 'boolean' && typeof e.reason === 'string'))) return;
    sessions = structuredClone(saved.sessions);
    selected = data.some(d => d.id === snapshot.modelContent.selectedDn) ? snapshot.modelContent.selectedDn : data[0].id;
    stage = ['landing', 'document', 'count', 'summary', 'scan'].includes(saved.stage) ? saved.stage : 'landing';
    if (stage === 'scan') stage = 'count';
    search = typeof saved.search === 'string' ? saved.search : '';
    filter = ['all', 'pending', 'verified'].includes(saved.filter) ? saved.filter : 'all';
  }
  function goto(next) { stage = next; scan = { state: 'searching', article: '', target: null, accepted: false }; closeSheet(); render(); save(); }
  function openDn(id) { selected = id; search = ''; filter = 'all'; goto(current().submitted ? 'summary' : current().finalised ? 'count' : 'document'); }
  function sourceRow(row) {
    return `<section class="ss-card" data-row="${safe(row.id)}"><div class="ss-row"><h3 class="ss-code">${safe(row.article)}</h3><span>${row.expected} PC</span></div><div>${safe(row.product)}</div><div class="ss-row"><span class="ss-meta">Page ${row.page} · Receiving row ${current().rows.indexOf(row) + 1}</span>${button('correct', 'Source / correct', false, current().submitted, `data-id="${row.id}"`)}</div></section>`;
  }
  function countRow(row) {
    const done = row.status === 'verified';
    const delta = row.qty - row.expected;
    return `<section class="ss-card" data-row="${row.id}"><div class="ss-row"><h3 class="ss-code">${safe(row.article)}</h3><span class="ss-badge ${done ? 'good' : row.status === 'recheck' ? 'warn' : ''}">${statusLabel(row)}</span></div>
      <p>${safe(row.product)}</p><div class="ss-meta">DN page ${row.page} · Row ${current().rows.indexOf(row) + 1}</div>
      <div class="ss-row ss-rule"><span>Expected on DN</span><span>${row.expected} PC</span></div>
      <div class="ss-row"><span>Physical count</span><span class="ss-value">${row.status === 'untouched' ? '—' : row.qty + ' PC'}</span></div>
      <div class="ss-meta">${row.scanned} scanned · ${row.manual} manual${done ? ` · ${delta ? 'Variance ' + signed(delta) + ' PC' : 'Matches DN'}` : ''}</div>
      ${done && delta ? `<p class="ss-warn">${safe(row.reason)}</p>` : ''}
      ${current().submitted ? '' : `<div class="ss-actions">${button('row-scan', 'Scan can', true, !current().finalised, `data-id="${row.id}"`)}${button(done ? 'reopen' : 'finish', done ? 'Reopen count' : 'Finish count', false, !current().finalised || row.status === 'untouched', `data-id="${row.id}"`)}</div>${button('manual', row.status === 'untouched' ? 'Manual count / zero received' : 'Manual count / correction', false, !current().finalised, `data-id="${row.id}"`)}`}
    </section>`;
  }
  function renderCountRows() {
    const container = main.querySelector('.ss-count-rows');
    if (!container) return;
    const rows = current().rows.filter(row => (!search || row.article.includes(search) || row.product.toLowerCase().includes(search.toLowerCase())) && (filter === 'all' || (filter === 'verified' ? row.status === 'verified' : row.status !== 'verified')));
    container.innerHTML = rows.length ? rows.map(countRow).join('') : '<p class="ss-meta">No receiving rows in this view.</p>';
  }
  function render() {
    const s = current(); const d = fixture();
    app.style.setProperty('--ss-card-padding', designs.spacing === 'Compact' ? '10px' : '14px');
    preview.hidden = stage !== 'scan';
    header.innerHTML = `<div class="ss-header-row"><span class="ss-brand">Pixorex · Sea Stock</span>${stage === 'landing' ? '' : button('landing', 'Delivery notes')}</div><h2>${stage === 'landing' ? 'Delivery notes' : 'DN ' + safe(s.id)}</h2><div class="ss-meta">${stage === 'landing' ? 'Document → Can count → Receiving summary' : safe(d.label) + ' · ' + (s.submitted ? 'Saved locally' : s.finalised ? 'Document finalised · rev ' + s.revision : 'Document review')}</div>`;
    nav.innerHTML = stage === 'landing' ? '' : [['document', '1 · Document'], ['count', '2 · Physical count'], ['summary', '3 · Summary']].map(([value, label]) => `<button type="button" data-stage="${value}" class="cursor-interaction" ${((stage === 'scan' ? 'count' : stage) === value) ? 'aria-current="step"' : ''} ${value === 'count' && !s.finalised ? 'disabled' : ''}>${label}</button>`).join('');
    if (stage === 'landing') {
      main.innerHTML = `<h3>Receive against a delivery note</h3><p class="ss-meta">Finalise the paper, then scan each physical can.</p>${button('new', 'New delivery note', true)}<div class="ss-rule"><h3>Saved delivery notes</h3></div>${sessions.map(item => {
        const dn = data.find(dn => dn.id === item.id);
        const label = item.submitted ? 'Saved locally' : item.finalised ? total(item, 'qty') ? 'Counting' : 'Ready to count' : 'Ready to finalise';
        return `<section class="ss-card"><div class="ss-row"><h3>${safe(item.id)}</h3><span class="ss-badge ${item.submitted ? 'good' : ''}">${label}</span></div><div class="ss-meta">${safe(dn.label)} · ${dn.pages} pages</div><div class="ss-row ss-rule"><span>Accepted physical count</span><span>${total(item, 'qty')} / ${total(item, 'expected')} PC</span></div><div class="ss-meta">${verified(item)} / ${item.rows.length} receiving rows verified</div><div class="ss-actions">${button('open-dn', item.submitted ? 'View saved form' : item.finalised ? total(item, 'qty') ? 'Resume can count' : 'Start can count' : 'Review document', true, false, `data-dn="${item.id}"`)}</div></section>`;
      }).join('')}`;
      footer.innerHTML = '<div class="ss-meta">Counts belong to the selected DN.</div>';
    } else if (stage === 'document') {
      main.innerHTML = `<div class="ss-row"><h3>Document summary</h3><span class="ss-badge ${s.finalised ? 'good' : ''}">${s.finalised ? 'Finalised' : sourceReady(s) ? 'Source checked' : 'Review pending'}</span></div>
        <section class="ss-card"><div class="ss-row"><span>Reviewed pages</span><span>${s.checked.length} / ${d.pages}</span></div><div class="ss-row"><span>Receiving rows / unique articles</span><span>${s.rows.length} / ${new Set(s.rows.map(r => r.article)).size}</span></div><div class="ss-row"><span>Expected on DN</span><span class="ss-value">${total(s, 'expected')} PC</span></div><div class="ss-meta">Printed Piece: ${d.piece} PC · Physical counts remain separate.</div>${summaryMismatch(s) ? `<p class="ss-warn">The item total differs from the printed Piece summary.</p><label class="ss-check"><input type="checkbox" class="ss-summary-review" ${s.summaryReviewed ? 'checked' : ''} ${s.submitted ? 'disabled' : ''}><span>I checked this summary discrepancy against the DN.</span></label>` : ''}</section>
        <details><summary>DN page checks · ${s.checked.length}/${d.pages}</summary>${Array.from({ length: d.pages }, (_, i) => `<div class="ss-row ss-rule"><span>Page ${i + 1} · Identity, content, coverage</span>${button('check-page', s.checked.includes(i + 1) ? 'Checked' : 'Confirm page checked', false, s.submitted, `data-page="${i + 1}"`)}</div>`).join('')}</details>
        <h3>Expected receiving articles</h3>${s.rows.map(sourceRow).join('')}`;
      footer.innerHTML = `<div class="ss-meta">${s.finalised ? 'This DN is the reference for each can match.' : 'Finalising records expected articles; it does not count stock.'}</div>${button(s.finalised ? 'count' : 'finalise', s.finalised ? s.submitted ? 'View physical counts' : 'Start / resume can count' : 'Finalise DN and start can count', true, !s.finalised && !sourceReady(s))}`;
    } else if (stage === 'count') {
      main.innerHTML = `<div class="ss-row"><h3>Physical can count</h3><span class="ss-badge ${s.finalised ? 'good' : 'warn'}">${s.finalised ? 'DN finalised' : 'Re-finalise DN'}</span></div>
        <section class="ss-card"><div class="ss-row"><span>Accepted physical count</span><span class="ss-value">${total(s, 'qty')} / ${total(s, 'expected')} PC</span></div><div class="ss-progress" role="progressbar" aria-label="Receiving rows verified" aria-valuemin="0" aria-valuemax="${s.rows.length}" aria-valuenow="${verified(s)}"><span style="width:${verified(s) / s.rows.length * 100}%"></span></div><div class="ss-meta">${verified(s)} / ${s.rows.length} rows verified · ${total(s, 'scanned')} scanned · ${total(s, 'manual')} manual</div>${s.submitted ? '' : `<div class="ss-actions">${button('scan', 'Scan next can', true, !s.finalised)}</div>`}</section>
        ${pending(s) ? `<p class="ss-warn">${pending(s)} unexpected article${pending(s) === 1 ? '' : 's'} need review in the summary.</p>` : ''}
        <input class="ss-search" type="search" placeholder="Search article or DN description" aria-label="Search receiving articles" value="${safe(search)}">
        <div class="ss-filters" aria-label="Receiving row status">${[['all', 'All'], ['pending', 'To verify'], ['verified', 'Verified']].map(([value, label]) => `<button type="button" data-filter="${value}" aria-pressed="${filter === value}" class="cursor-interaction">${label}</button>`).join('')}</div><div class="ss-count-rows"></div>`;
      renderCountRows();
      footer.innerHTML = `<div class="ss-meta">${s.submitted ? 'Saved locally · Read only' : 'Only a deliberate accepted can adds +1.'}</div>${button('summary', 'Review count summary', true)}`;
    } else if (stage === 'scan') {
      renderScan();
    } else {
      const variances = s.rows.filter(r => r.status === 'verified' && r.qty !== r.expected);
      main.innerHTML = `<div class="ss-row"><h3>${s.submitted ? 'Receiving form saved' : 'Receiving summary'}</h3><span class="ss-badge ${s.submitted || ready(s) ? 'good' : 'warn'}">${s.submitted ? 'Saved locally' : ready(s) ? 'Ready to submit' : 'Checks pending'}</span></div>
        <section class="ss-card"><div class="ss-row"><span>Expected on DN</span><span>${total(s, 'expected')} PC</span></div><div class="ss-row"><span>Saved running count</span><span class="ss-value">${total(s, 'qty')} PC</span></div><div class="ss-row"><span>Verified physical count</span><span>${s.rows.filter(r => r.status === 'verified').reduce((n, r) => n + r.qty, 0)} PC</span></div><div class="ss-rule ss-meta">${s.checked.length}/${d.pages} DN pages checked · ${s.finalised ? 'Finalised' : 'Not finalised'} · ${verified(s)}/${s.rows.length} receiving rows verified<br>${total(s, 'scanned')} scan-confirmed units · ${total(s, 'manual')} manually recorded units</div></section>
        <section class="ss-card"><h3>Completed variances · ${variances.length}</h3>${variances.length ? variances.map(row => `<div class="ss-rule"><div class="ss-row"><span class="ss-code">${safe(row.article)} · Page ${row.page}</span><span class="ss-warn">${signed(row.qty - row.expected)} PC</span></div><div class="ss-meta">DN ${row.expected} · Count ${row.qty} · ${safe(row.reason)}</div></div>`).join('') : '<p class="ss-meta">No completed variances. Pending rows remain to verify.</p>'}</section>
        <section class="ss-card"><h3>Unexpected articles · ${pending(s)} unresolved</h3>${s.exceptions.length ? s.exceptions.map((e, i) => `<div class="ss-rule"><div class="ss-row"><span class="ss-code">${safe(e.article)}</span><span class="ss-badge ${e.resolved ? 'good' : 'bad'}">${e.resolved ? 'Set aside' : 'Not on DN'}</span></div><div class="ss-meta">No count added${e.resolved ? ' · ' + safe(e.reason) : ''}</div>${e.resolved || s.submitted ? '' : button('resolve', 'Record disposition', false, false, `data-exception="${i}"`)}</div>`).join('') : '<p class="ss-meta">No unexpected article events recorded.</p>'}</section>
        <h3>All receiving rows</h3>${s.rows.map(row => `<section class="ss-card"><div class="ss-row"><h3 class="ss-code">${safe(row.article)}</h3><span class="ss-badge ${row.status === 'verified' ? 'good' : 'warn'}">${statusLabel(row)}</span></div><div class="ss-meta">${safe(row.product)} · Page ${row.page}</div><div class="ss-row"><span>Expected ${row.expected} PC</span><span>Count ${row.status === 'untouched' ? '—' : row.qty + ' PC'}</span></div></section>`).join('')}
        ${s.submitted ? '<p class="ss-good">Immutable receiving form saved on this device.</p>' : !ready(s) ? '<p class="ss-warn">Finalise the document, finish every row, and resolve unexpected articles before submitting.</p>' : ''}`;
      footer.innerHTML = `<div class="ss-meta">${s.submitted ? 'Counts and reasons retained in the saved form.' : 'Submit saves the receiving form on this device.'}</div>${button('submit', s.submitted ? 'Saved locally' : 'Confirm and submit locally', true, s.submitted || !ready(s))}${button('count', s.submitted ? 'View physical counts' : 'Back to physical count')}`;
    }
  }
  function renderScan() {
    const s = current();
    const matches = scan.state === 'matched' ? matchRows(scan.article) : [];
    const target = rowById(scan.target);
    const good = matches.length && target;
    const labels = { searching: ['Searching', 'Find the printed Article no. field.'], verifying: ['Verifying article', 'Hold steady while the article is confirmed.'], blur: ['Hold steady', 'The article is blurred. Keep scanning.'], glare: ['Reduce glare', 'Tilt the can or camera slightly.'], hidden: ['Article not visible', 'Rotate the can slightly to show Article no.'], conflict: ['Article not confirmed', 'Conflicting readings. Keep scanning.'], matched: ['Article matched', 'Exact article found on this DN.'], unexpected: ['Not on this DN', 'This article is absent from the current DN.'] };
    const [title, guidance] = scan.accepted ? ['One can saved', 'Move this can aside, then scan the next can.'] : labels[scan.state] || labels.searching;
    main.innerHTML = `<div class="ss-row"><h3>Scan can article</h3><span class="ss-badge">Receiving · PC</span></div><div class="ss-camera" role="img" aria-label="Simulated camera observation"><span class="ss-meta">Camera preview · Simulation</span><div class="ss-label ${scan.state}">${['hidden', 'searching'].includes(scan.state) ? '<span class="ss-meta">Article field outside the visible area</span>' : `<span class="ss-meta">Printed Article no.</span><div class="ss-value ss-code">${safe(scan.article || '00464138')}</div>`}</div><span class="ss-meta">Show the article field on the can.</span></div>
      <section class="ss-card"><div class="ss-row"><h3>${title}</h3><span class="ss-badge ${scan.accepted || good ? 'good' : scan.state === 'unexpected' ? 'bad' : ''}">${scan.accepted ? '+1 saved' : scan.state === 'matched' && matches.length > 1 ? 'Choose row' : scan.state === 'matched' ? 'DN match' : 'No count added'}</span></div><p>${guidance}</p>
      ${scan.article ? `<div class="ss-row"><span>Article</span><span class="ss-value ss-code">${safe(scan.article)}</span></div>` : ''}
      ${matches.length > 1 && !scan.accepted ? `<p class="ss-warn">This article appears in ${matches.length} receiving rows. Choose one.</p><div class="ss-allocation">${matches.map(row => `<button type="button" data-action="allocate" data-id="${row.id}" aria-pressed="${scan.target === row.id}" class="cursor-interaction">Page ${row.page} · Row ${s.rows.indexOf(row) + 1}<br>${safe(row.product)}<br>DN ${row.expected} PC · Counted ${row.qty} PC</button>`).join('')}</div>` : ''}
      ${target ? `<div class="ss-rule"><p>${safe(target.product)}</p><div class="ss-meta">DN ${safe(s.id)} · Page ${target.page} · Row ${s.rows.indexOf(target) + 1}</div><div class="ss-row"><span>Expected on DN</span><span>${target.expected} PC</span></div><div class="ss-row"><span>Saved physical count</span><span>${target.qty} PC</span></div>${target.status === 'verified' && !scan.accepted ? '<p class="ss-warn">This row is finished. Reopen its count before adding another can.</p>' : ''}</div>` : ''}</section>
      ${scan.state === 'unexpected' ? `<div class="ss-actions">${button('unexpected', 'Set aside / record unexpected article')}${button('document', 'Review this DN')}</div>` : ''}
      ${designs.diagnostics ? `<div class="ss-debug">TEST VIEW · ${safe(scan.state.toUpperCase())} · Visual confirmation: ${scan.state === 'matched' || scan.state === 'unexpected' ? '2 usable frames (simulated)' : 'pending'} · Current-DN matches: ${matches.length}</div>` : ''}`;
    footer.innerHTML = `<div class="ss-meta">${s.finalised ? 'Validated against the finalised articles in DN ' + safe(s.id) : 'Document changed. Re-finalise the DN to continue.'}</div>${button(scan.accepted ? 'next' : 'accept', scan.accepted ? 'Scan next can' : 'Add this can (+1)', true, !scan.accepted && (!s.finalised || !good || target.status === 'verified' || s.submitted))}${scan.accepted ? button('undo', 'Undo this can') : ''}${button('count', 'Back to count list')}`;
  }
  function previewScan(state = root.querySelector('.ss-observation').value, article = root.querySelector('.ss-observed-article').value.trim()) {
    if (!current().finalised || current().submitted) return;
    if (scan.accepted) { announce('This can is already saved. Choose Scan next can before accepting another.'); return; }
    if (state === 'unexpected') article = '00464138';
    if (state === 'duplicate') { article = '475210'; state = 'matched'; }
    const matches = matchRows(article);
    if (state === 'matched') state = /^\d+$/.test(article) && matches.length ? 'matched' : 'unexpected';
    if (state === 'unexpected' && matches.length) state = 'matched';
    scan = { state, article: ['searching', 'hidden'].includes(state) ? '' : article, target: state === 'matched' && matches.length === 1 ? matches[0].id : null, accepted: false };
    render(); announce(state === 'matched' ? 'Exact article matches the current DN. Count unchanged until accepted.' : 'No can added.');
  }
  function closeSheet() {
    overlay.hidden = true; overlay.innerHTML = '';
    if (returnFocus?.isConnected) returnFocus.focus();
    returnFocus = null;
    header.inert = false; nav.inert = false; main.inert = false; footer.inert = false;
  }
  function sheet(title, contents) {
    returnFocus = document.activeElement;
    overlay.innerHTML = `<section class="ss-sheet" role="dialog" aria-modal="true" aria-labelledby="ss-sheet-title"><h3 id="ss-sheet-title">${title}</h3>${contents}</section>`;
    overlay.hidden = false;
    header.inert = true; nav.inert = true; main.inert = true; footer.inert = true;
    overlay.querySelector('input,select,button')?.focus();
  }
  function formActions(label) { return `<div class="ss-error" role="alert"></div><div class="ss-actions">${button('cancel', 'Cancel')}${button('save-form', label, true)}</div>`; }
  function startScan(article = '') {
    if (!current().finalised || current().submitted) return;
    stage = 'scan';
    root.querySelector('.ss-observation').value = 'matched';
    root.querySelector('.ss-observed-article').value = article || current().rows.find(r => r.status !== 'verified')?.article || current().rows[0].article;
    scan = { state: 'searching', article: '', target: null, accepted: false };
    render(); save(); announce('Camera observation is simulated. Use the preview controls to show a scan.');
  }
  function finishRow(row) {
    if (!row || !current().finalised || row.status === 'untouched' || current().submitted) return;
    if (row.qty === row.expected) { row.status = 'verified'; row.reason = ''; render(); save(); announce('Physical count verified for ' + row.article); return; }
    sheet('Finish physical count', `<p>Article ${safe(row.article)} · DN ${row.expected} PC · Physical ${row.qty} PC</p><p class="ss-warn">${row.qty < row.expected ? 'Shortage' : 'Excess'} ${Math.abs(row.qty - row.expected)} PC</p><form data-form="finish" data-id="${row.id}"><label for="ss-reason">Variance reason</label><select id="ss-reason" name="reason" required><option value="">Choose a reason</option>${(row.qty < row.expected ? ['Short received', 'Not received', 'Damaged cans excluded', 'Other'] : ['Extra received', 'Other']).map(r => `<option>${r}</option>`).join('')}</select><label for="ss-details">Details (required for Other)</label><textarea id="ss-details" name="details" rows="2"></textarea>${formActions('Verify count')}</form>`);
  }
  root.addEventListener('input', event => {
    if (!event.target.matches('.ss-search')) return;
    search = event.target.value.trim(); renderCountRows(); save();
  });
  root.addEventListener('change', event => {
    if (!event.target.matches('.ss-summary-review') || current().submitted) return;
    current().summaryReviewed = event.target.checked; current().finalised = false; render(); save();
  });
  root.addEventListener('click', event => {
    const control = event.target.closest('button');
    if (!control || control.disabled || !root.contains(control)) return;
    const action = control.dataset.action;
    const s = current();
    if (control.dataset.stage) { goto(control.dataset.stage); return; }
    if (control.dataset.filter) { filter = control.dataset.filter; render(); save(); return; }
    if (action === 'cancel') { closeSheet(); return; }
    if (action === 'save-form') { const form = control.closest('form'); if (form?.reportValidity()) submitForm(form); return; }
    if (['landing', 'document', 'count', 'summary'].includes(action)) { if (action === 'count' && !s.finalised) goto('document'); else goto(action); return; }
    if (action === 'open-dn') { openDn(control.dataset.dn); return; }
    if (action === 'new') { sheet('Capture a delivery note', `<p>Scan every printed page, check articles and quantities, then finalise the document.</p><div class="ss-meta">Wireframe uses captured fixture data.</div><div class="ss-actions">${button('cancel', 'Close')}${button('new-fixture', 'Open captured DN fixture', true)}</div>`); return; }
    if (action === 'new-fixture') { selected = data[0].id; goto('document'); return; }
    if (action === 'check-page' && !s.submitted) { const page = Number(control.dataset.page); s.checked = s.checked.includes(page) ? s.checked.filter(p => p !== page) : [...s.checked, page]; s.finalised = false; s.rows.filter(r => r.page === page && r.status === 'verified').forEach(r => { r.status = 'recheck'; }); render(); save(); return; }
    if (action === 'finalise') { if (sourceReady(s) && !s.submitted) { s.finalised = true; goto('count'); announce('DN finalised. Physical count starts from zero for untouched rows.'); } return; }
    if (action === 'scan' || action === 'next') { startScan(); return; }
    if (action === 'preview') { previewScan(); return; }
    if (action === 'allocate' && !scan.accepted) { scan.target = control.dataset.id; render(); announce('Receiving row selected. No can added yet.'); return; }
    if (action === 'accept') {
      const row = rowById(scan.target);
      if (s.submitted || !s.finalised || scan.accepted || scan.state !== 'matched' || !row || row.article !== scan.article || row.status === 'verified') return;
      row.qty++; row.scanned++; row.status = 'counting'; row.reason = '';
      s.events.push({ id: `${Date.now()}:${++serial}`, article: row.article, row: row.id, delta: 1, method: 'scan', revision: s.revision });
      scan.accepted = true; render(); save(); announce('One can saved for article ' + row.article + '. Count ' + row.qty + ' PC.'); return;
    }
    if (action === 'undo') {
      const row = rowById(scan.target);
      if (!scan.accepted || !row || s.submitted || row.scanned < 1) return;
      row.qty--; row.scanned--; row.status = 'counting'; row.reason = '';
      s.events.push({ id: `${Date.now()}:${++serial}`, article: row.article, row: row.id, delta: -1, method: 'undo', revision: s.revision });
      scan.accepted = false; render(); save(); announce('Last accepted can undone. Count history retained.'); return;
    }
    if (action === 'unexpected') {
      if (s.submitted || scan.state !== 'unexpected' || !scan.article || !/^\d+$/.test(scan.article) || matchRows(scan.article).length) return;
      s.exceptions.push({ article: scan.article, resolved: false, reason: '' }); goto('summary'); announce('Unexpected article recorded. Physical count unchanged.'); return;
    }
    if (action === 'resolve' && !s.submitted) { sheet('Set unexpected can aside', `<p>Article ${safe(s.exceptions[Number(control.dataset.exception)].article)} · No count was added to this DN.</p><form data-form="resolve" data-exception="${control.dataset.exception}"><label for="ss-disposition">Disposition / reason</label><input id="ss-disposition" name="reason" required placeholder="Wrong delivery; can set aside">${formActions('Save disposition')}</form>`); return; }
    if (action === 'submit') { if (ready(s) && !s.submitted) { s.submitted = true; render(); save(); announce('Receiving form saved locally.'); } return; }
    const row = rowById(control.dataset.id);
    if (!row || s.submitted) return;
    if (action === 'row-scan') { startScan(row.article); return; }
    if (action === 'reopen' && s.finalised) { row.status = 'counting'; row.reason = ''; render(); save(); announce('Count reopened; total retained.'); return; }
    if (action === 'finish') { finishRow(row); return; }
    if (action === 'manual' && s.finalised) {
      sheet('Manual count / correction', `<p>Article ${safe(row.article)} · Page ${row.page} · DN ${row.expected} PC</p><div class="ss-meta">Manually recorded quantities are shown separately from scanned cans.</div><form data-form="manual" data-id="${row.id}"><label for="ss-quantity">Total manually counted cans</label><input id="ss-quantity" name="quantity" type="number" min="0" step="1" required value="${row.manual}"><div class="ss-meta">${row.scanned} scan-confirmed cans retained. New total = scanned + manual.</div><label for="ss-manual-reason">Reason</label><input id="ss-manual-reason" name="reason" required placeholder="Label unreadable / zero received / correction">${formActions('Save manual count')}</form>`); return;
    }
    if (action === 'correct') { sheet('DN source correction', `<p>Article ${safe(row.article)} · Page ${row.page}</p><div class="ss-meta">Saved can counts are retained. Correction requires source and physical recheck.</div><form data-form="correct" data-id="${row.id}"><label for="ss-expected">Verified printed quantity · PC</label><input id="ss-expected" name="quantity" type="number" min="0" step="1" required value="${row.expected}"><label for="ss-correction-reason">Correction reason</label><input id="ss-correction-reason" name="reason" required>${formActions('Save DN correction')}</form>`); }
  });
  function submitForm(form) {
    const s = current(); if (s.submitted) return;
    const fields = new FormData(form); const error = form.querySelector('.ss-error');
    const reason = String(fields.get('reason') || '').trim();
    if (!reason) { error.textContent = 'Enter a reason.'; return; }
    const row = rowById(form.dataset.id);
    if (form.dataset.form === 'resolve') {
      const item = s.exceptions[Number(form.dataset.exception)]; if (!item) return;
      item.resolved = true; item.reason = reason;
    } else if (form.dataset.form === 'finish') {
      if (!row || !s.finalised) return;
      const detail = String(fields.get('details') || '').trim();
      if (reason === 'Other' && !detail) { error.textContent = 'Explain the variance for Other.'; return; }
      row.reason = detail ? reason + ': ' + detail : reason; row.status = 'verified';
    } else {
      if (!row) return;
      const raw = String(fields.get('quantity') || '').trim(); const quantity = Number(raw);
      if (!/^\d+$/.test(raw) || !Number.isSafeInteger(quantity) || quantity < 0 || quantity > 100000) { error.textContent = 'Enter a whole quantity between zero and 100000.'; return; }
      if (form.dataset.form === 'manual') {
        if (!s.finalised) return;
        const before = row.qty; row.manual = quantity; row.qty = row.scanned + quantity; row.status = 'counting'; row.reason = '';
        s.events.push({ id: `${Date.now()}:${++serial}`, article: row.article, row: row.id, delta: row.qty - before, method: 'manual', reason, revision: s.revision });
      } else if (form.dataset.form === 'correct') {
        if (row.expected !== quantity) {
          row.expected = quantity; s.finalised = false; s.summaryReviewed = false; s.revision++; s.checked = s.checked.filter(p => p !== row.page); if (row.status !== 'untouched') row.status = 'recheck'; row.reason = '';
        }
      }
    }
    closeSheet(); render(); save(); announce('Saved in the workflow preview.');
  }
  root.addEventListener('submit', event => { event.preventDefault(); if (event.target.reportValidity()) submitForm(event.target); });
  root.addEventListener('keydown', event => {
    if (overlay.hidden) return;
    if (event.key === 'Escape') { event.preventDefault(); closeSheet(); }
    if (event.key === 'Tab') {
      const controls = [...overlay.querySelectorAll('input,select,textarea,button')].filter(c => !c.disabled);
      if (event.shiftKey && document.activeElement === controls[0]) { event.preventDefault(); controls.at(-1)?.focus(); }
      else if (!event.shiftKey && document.activeElement === controls.at(-1)) { event.preventDefault(); controls[0]?.focus(); }
    }
  });
  restore(window.openai?.widgetState);
  render();
  window.addEventListener('openai:set_globals', event => {
    const snapshot = event.detail?.globals?.widgetState;
    if (!snapshot || snapshot.privateContent?.writeId === lastWriteId) return;
    restore(snapshot); scan = { state: 'searching', article: '', target: null, accepted: false }; closeSheet(); render();
  });
  if (globalThis.Tweak) {
    const tweak = new Tweak({ container: app, onChange: () => { render(); save(); } });
    tweak.addSelect(designs, 'spacing', { label: 'Row spacing', options: ['Comfortable', 'Compact'] });
    tweak.addToggle(designs, 'diagnostics', { label: 'Scanner test diagnostics' });
  }
})();
