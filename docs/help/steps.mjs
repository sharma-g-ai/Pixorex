// The steps and highlight boxes for take.mjs (spliced in between `try {` and `} catch`).
// A mark is [what it is, JS expression that finds the element on the page].
const field = (label, scope = 'document') =>
  `[...(${scope === 'dialog' ? "Q('dialog[open]')" : 'document'}).querySelectorAll('label')].find((l) => l.textContent.trim() === ${JSON.stringify(label)}).parentElement`
const card = (title) => `C(${JSON.stringify(title)}, 'section', 'h2')`
const table = (name) => `Q('[role=table][aria-label=${JSON.stringify(name)}]')`
const button = (text) => `T(${JSON.stringify(text)}, 'button')`
const link = (text) => `T(${JSON.stringify(text)}, 'a')`
const SIDEBAR = [
  ['Scope card', "Q('aside > div:nth-of-type(2)')"],
  ['Menu', "Q('nav[aria-label=Main]')"],
  ['Your name, role and sign out', "Q('aside > div:last-child')"],
]
const FILTERS = "Q('main .items-end.flex-wrap')"
const TABS = "Q('main [role=tablist]')"
const DIALOG = "Q('dialog[open]')"

export const steps = `
  // ---- Sign in ----
  await go('/sign-in')
  await js("sessionStorage.removeItem('seastock.data')")
  await shot('01-sign-in', { full: false, marks: [
    ['Work e-mail', ${JSON.stringify(field('Work e-mail'))}],
    ['Password', ${JSON.stringify(field('Password'))}],
    ['Sign in', "Q('button[type=submit]')"],
    ['Forgot password?', ${JSON.stringify(button('Forgot password?'))}],
    ['Reset sample data', "T('Reset sample data', 'button').parentElement"],
  ] })
  await fill('Work e-mail', 'dana.whitfield@ppg.example')
  await fill('Password', 'wrong-password')
  await click('Sign in', 'page', 'button[type=submit]')
  await shot('02-sign-in-error', { full: false, marks: [['Error message', "Q('[role=alert]')"]] })
  await click('Forgot password?')
  await shot('03-forgot-password', { full: false, marks: [
    ['Work e-mail', ${JSON.stringify(field('Work e-mail'))}],
    ['Send reset link', ${JSON.stringify(button('Send reset link'))}],
    ['Back to sign in', ${JSON.stringify(button('Back to sign in'))}],
  ] })
  await click('Send reset link')
  await shot('04-check-email', { full: false, marks: [['Back to sign in', ${JSON.stringify(button('Back to sign in'))}]] })

  // ---- Overview ----
  await go('/overview', 'u01')
  await shot('10-overview', { marks: [
    ...${JSON.stringify(SIDEBAR)},
    ['Page title and scope', "Q('main header')"],
    ['Summary tiles', "Q('main .overflow-y-auto > .grid')"],
    ['Late or no sync', ${JSON.stringify(card('Late or no sync'))}],
    ['Negative stock', ${JSON.stringify(card('Negative stock'))}],
    ['Unrecognised scans', ${JSON.stringify(card('Unrecognised scans'))}],
    ['Match to article', ${JSON.stringify(button('Match to article'))}],
    ['Recent activity', ${JSON.stringify(card('Recent activity'))}],
  ] })
  await js("[...document.querySelectorAll('button')].filter((b) => b.textContent.trim() === 'Match to article').pop().click()")
  await sleep(500)
  await shot('11-match-to-article', { full: false, marks: [
    ['What the label said', "Q('dialog[open] p')"],
    ['Suggested article', "Q('dialog[open] .bg-brand-tint')"],
    ['Article on the master item list', ${JSON.stringify(field('Article on the master item list', 'dialog'))}],
    ['Match and post', "T('Match and post', 'button')"],
  ] })
  await click('Cancel', 'dialog')
  await go('/overview', 'u06')
  await shot('12-overview-customer-admin', { marks: [
    ['Scope card', "Q('aside > div:nth-of-type(2)')"],
    ['Menu', "Q('nav[aria-label=Main]')"],
    ['Summary tiles', "Q('main .overflow-y-auto > .grid')"],
  ] })

  // ---- Sea Stock ----
  await go('/sea-stock', 'u01')
  await shot('20-sea-stock-by-product', { marks: [
    ['Filters', ${JSON.stringify(FILTERS)}],
    ['Export summary', ${JSON.stringify(button('Export summary'))}],
    ['Export detail', ${JSON.stringify(button('Export detail'))}],
    ['Group by', ${JSON.stringify(TABS)}],
    ['Totals for what is shown', "Q('main section .min-h-12 > span')"],
    ['Stock by product', ${JSON.stringify(table('Sea Stock'))}],
    ['Total line', "Q('main section .justify-end.gap-6')"],
  ] })
  await click('By vessel')
  await shot('21-sea-stock-by-vessel', { marks: [
    ['Vessel name (click to open)', "Q('[role=table] [role=row]:nth-child(2) button')"],
    ['Last sync', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:last-child')"],
  ] })
  await click('By customer')
  await shot('22-sea-stock-by-customer', { marks: [['Oldest sync', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:last-child')"]] })
  await click('By region')
  await shot('23-sea-stock-by-region', { marks: [['One row per region', "Q('[role=table] [role=row]:nth-child(2)')"]] })
  await go('/sea-stock?vessel=v01', 'u01')
  await shot('24-sea-stock-one-vessel', { marks: [
    ['Vessel details', ${JSON.stringify(card('Nordhavn Aurora'))}],
    ['Consumption and Activity links', "T('Consumption →', 'a').parentElement"],
    ['Last sync', "T('Last sync', 'div').parentElement"],
    ['Stock on this vessel', ${JSON.stringify(table('Sea Stock'))}],
  ] })
  await go('/sea-stock', 'u12')
  await shot('25-sea-stock-ship-admin', { marks: [
    ['Menu for a Ship Admin', "Q('nav[aria-label=Main]')"],
    ['Your vessel', ${JSON.stringify(card('Nordhavn Aurora'))}],
  ] })
  await go('/sea-stock?vessel=v12', 'u01')
  await shot('26-sea-stock-no-opening-stock', { marks: [['Opening stock not captured', "Q('main [class*=bg-warning-soft]')"]] })

  // ---- Consumption ----
  await go('/consumption', 'u01')
  await shot('30-consumption-by-product', { marks: [
    ['Period', ${JSON.stringify(field('Period'))}],
    ['Filters', ${JSON.stringify(FILTERS)}],
    ['Export summary', ${JSON.stringify(button('Export summary'))}],
    ['Export detail', ${JSON.stringify(button('Export detail'))}],
    ['Group by', ${JSON.stringify(TABS)}],
    ['Period and totals', "Q('main section .justify-between > span')"],
    ['Consumption table', "Q('main [role=table]')"],
    ['Share of liters bar', "Q('main [role=table] [role=row]:nth-child(2) [role=cell]:nth-child(2)')"],
    ['How consumption is counted', "Q('main .bg-brand-tint')"],
  ] })
  await click('By vessel')
  await shot('31-consumption-by-vessel', { marks: [['One row per vessel', "Q('main [role=table] [role=row]:nth-child(2)')"]] })
  await fill('Period', 'custom')
  await shot('32-consumption-custom-dates', { marks: [
    ['From', ${JSON.stringify(field('From'))}],
    ['To', ${JSON.stringify(field('To'))}],
  ] })

  // ---- Activity ----
  await go('/activity', 'u01')
  await shot('40-activity-transactions', { marks: [
    ['Transactions / Delivery notes', ${JSON.stringify(TABS)}],
    ['Filters', ${JSON.stringify(FILTERS)}],
    ['Export CSV', ${JSON.stringify(button('Export CSV'))}],
    ['Count', "Q('main section .justify-end > span')"],
    ['Recorded and synced', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(1)')"],
    ['Type', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(3)')"],
    ['Item', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(4)')"],
    ['Change', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(5)')"],
    ['By / device', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(6)')"],
    ['Source / reason', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(7)')"],
  ] })
  await click('Delivery notes')
  await shot('41-activity-delivery-notes', { marks: [
    ['Tally and Search filters', ${JSON.stringify(FILTERS)}],
    ['Delivery note (click to open)', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(1) a')"],
    ['Tally result', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(6)')"],
    ['Received', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(7)')"],
  ] })
  await go('/activity?tab=notes&dn=5324641215', 'u01')
  await shot('42-delivery-note', { full: false, marks: [
    ['Header read from the note', ${JSON.stringify(card('Header'))}],
    ['Tally, line by line', ${JSON.stringify(card('Tally'))}],
    ['Result of a line', "Q('dialog[open] [role=table] [role=row]:nth-child(4) [role=cell]:nth-child(7)')"],
    ['Reason given by the crew', "Q('dialog[open] [role=table] [role=row]:nth-child(4) [role=cell]:nth-child(8)')"],
  ] })

  // ---- Customers & vessels ----
  await go('/admin/customers', 'u01')
  await shot('50-customers', { marks: [
    ['Tabs', ${JSON.stringify(TABS)}],
    ['Add customer', ${JSON.stringify(button('Add customer'))}],
    ['Filters', ${JSON.stringify(FILTERS)}],
    ['Customers table', "Q('[role=table]')"],
    ['Edit', ${JSON.stringify(button('Edit'))}],
  ] })
  await click('Add customer')
  await shot('51-add-customer', { full: false, marks: [
    ['Customer name', ${JSON.stringify(field('Customer name', 'dialog'))}],
    ['Customer ID', ${JSON.stringify(field('Customer ID (as in PPG systems)', 'dialog'))}],
    ['Region', ${JSON.stringify(field('Region', 'dialog'))}],
    ['Add customer', "Q('dialog[open] .justify-end button:last-child')"],
  ] })
  await click('Cancel', 'dialog')
  await click('Edit', 'page', 'button')
  await shot('52-edit-customer', { full: false, marks: [['Status', ${JSON.stringify(field('Status', 'dialog'))}]] })
  await click('Cancel', 'dialog')
  await click('Vessels')
  await shot('53-vessels', { marks: [
    ['Add vessel', ${JSON.stringify(button('Add vessel'))}],
    ['Filters', ${JSON.stringify(FILTERS)}],
    ['Tablet', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(4)')"],
    ['Opening stock', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(5)')"],
    ['Last sync', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(6)')"],
    ['Note about tablets', "Q('main .bg-brand-tint')"],
  ] })
  await click('Add vessel')
  await fill('IMO number', '12345', 'dialog')
  await shot('54-add-vessel', { full: false, marks: [
    ['Vessel name', ${JSON.stringify(field('Vessel name', 'dialog'))}],
    ['Vessel ID', ${JSON.stringify(field('Vessel ID (as in PPG systems)', 'dialog'))}],
    ['IMO number (with a check)', ${JSON.stringify(field('IMO number', 'dialog'))}],
    ['Customer', ${JSON.stringify(field('Customer', 'dialog'))}],
  ] })
  await click('Cancel', 'dialog')
  await click('Regions')
  await shot('55-regions', { marks: [
    ['Regions table', "Q('[role=table]')"],
    ['Edit', ${JSON.stringify(button('Edit'))}],
  ] })
  await click('Edit', 'page', 'button')
  await shot('56-edit-region', { full: false, marks: [['Region name', ${JSON.stringify(field('Region name', 'dialog'))}]] })
  await click('Cancel', 'dialog')

  // ---- Users ----
  await go('/admin/users', 'u01')
  await shot('60-users', { marks: [
    ['Tabs', ${JSON.stringify(TABS)}],
    ['Add user', ${JSON.stringify(button('Add user'))}],
    ['Filters', ${JSON.stringify(FILTERS)}],
    ['Role', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(2)')"],
    ['Scope', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(4)')"],
    ['Status', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(5)')"],
  ] })
  await click('Add user')
  await fill('Role', 'ppg-admin', 'dialog')
  await fill('Scope', 'regions', 'dialog')
  await shot('61-add-user-ppg-admin', { full: false, marks: [
    ['Name, job title, e-mail', "Q('dialog[open] .grid')"],
    ['Role', ${JSON.stringify(field('Role', 'dialog'))}],
    ['Scope', ${JSON.stringify(field('Scope', 'dialog'))}],
    ['Regions', "Q('dialog[open] fieldset')"],
    ['Add and send invite', "Q('dialog[open] .justify-end button:last-child')"],
  ] })
  await fill('Role', 'customer-admin', 'dialog')
  await shot('62-add-user-customer-admin', { full: false, marks: [['Customer', ${JSON.stringify(field('Customer', 'dialog'))}]] })
  await fill('Role', 'ship-admin', 'dialog')
  await shot('63-add-user-ship-admin', { full: false, marks: [['Vessel', ${JSON.stringify(field('Vessel', 'dialog'))}]] })
  await click('Cancel', 'dialog')
  await click('Edit', 'page', 'button')
  await shot('64-edit-user', { full: false, marks: [['Status', ${JSON.stringify(field('Status', 'dialog'))}]] })
  await click('Cancel', 'dialog')
  await click('Roles & permissions')
  await shot('65-roles', { marks: [
    ['The three roles', "Q('main [class*=grid-cols-3]')"],
    ['Permissions table', "Q('[role=table][aria-label=Permissions]')"],
  ] })
  await go('/admin/users', 'u06')
  await shot('66-users-customer-admin', { marks: [['Only your company', "Q('main [role=table]')"]] })

  // ---- Products ----
  await go('/admin/products', 'u01')
  await shot('70-master-item-list', { marks: [
    ['Tabs', ${JSON.stringify(TABS)}],
    ['Bulk load', ${JSON.stringify(button('Bulk load'))}],
    ['Add item', ${JSON.stringify(button('Add item'))}],
    ['Filters', ${JSON.stringify(FILTERS)}],
    ['Component', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(4)')"],
    ['Pack size and unit volume', "Q('[role=table] [role=row]:nth-child(2) [role=cell]:nth-child(6)')"],
    ['Retire', ${JSON.stringify(button('Retire'))}],
  ] })
  await click('Add item')
  await fill('Article number', '179061', 'dialog')
  await fill('Product type', '2K', 'dialog')
  await shot('71-add-item', { full: false, marks: [
    ['Article number (already used)', ${JSON.stringify(field('Article number', 'dialog'))}],
    ['Product type', ${JSON.stringify(field('Product type', 'dialog'))}],
    ['Component type', ${JSON.stringify(field('Component type', 'dialog'))}],
  ] })
  await click('Cancel', 'dialog')
  await click('Bulk load')
  await shot('72-bulk-load-empty', { full: false, marks: [['Choose a file', "Q('dialog[open] label.cursor-pointer')"]] })
  {
    const csv = join(OUT, '..', 'ppg-items.csv')
    writeFileSync(csv, 'article,product\\n')
    const { root } = await cdp('DOM.getDocument', { depth: -1, pierce: true })
    const { nodeId } = await cdp('DOM.querySelector', { nodeId: root.nodeId, selector: 'dialog[open] input[type=file]' })
    await cdp('DOM.setFileInputFiles', { nodeId, files: [csv] })
    await sleep(500)
  }
  await shot('73-bulk-load-preview', { full: false, marks: [
    ['What the file would do', "Q('dialog[open] .flex-col.gap-2')"],
    ['Load', "Q('dialog[open] .justify-end button:last-child')"],
  ] })
  await click('Cancel', 'dialog')
  await click('Retire', 'page', 'button')
  await shot('74-retire-item', { full: false, marks: [['Retire item', "Q('dialog[open] .justify-end button:last-child')"]] })
  await click('Cancel', 'dialog')
  await click('Label schema')
  await shot('75-label-schema', { marks: [
    ['Version', "Q('main [class*=min-h-10] > p')"],
    ['Discard and Publish', "Q('main [class*=min-h-10] > div')"],
    ['Fields read from the label', ${JSON.stringify(card('Fields read from the label'))}],
    ['Component-type rules', ${JSON.stringify(card('Component-type rules'))}],
    ['How matching works', "Q('main .bg-brand-tint')"],
  ] })
  await click('Edit', 'page', 'button')
  await shot('76-edit-label-field', { full: false, marks: [
    ['Required', ${JSON.stringify(field('Required', 'dialog'))}],
    ['Rule', ${JSON.stringify(field('Rule', 'dialog'))}],
  ] })
  await fill('Rule', '6 digits, no letters', 'dialog')
  await click('Save to draft', 'dialog')
  await shot('77-label-schema-unpublished', { full: false, marks: [['Unpublished changes', "Q('main [class*=min-h-10] > div')"]] })

  // ---- A limited PPG Admin ----
  await go('/overview', 'u02')
  await shot('80-ppg-admin-limited', { full: false, marks: [
    ['Scope card', "Q('aside > div:nth-of-type(2)')"],
    ['Menu without Administration', "Q('nav[aria-label=Main]')"],
  ] })
`
