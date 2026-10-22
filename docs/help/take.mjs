// Screenshots of the 8-screen SeaStock app for the help page, via Chrome's DevTools protocol.
// Records where each highlighted widget sits (shots.json). Steps come from steps.mjs.
// Usage: node take.mjs <outDir>
import { spawn } from 'node:child_process'
import { mkdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { steps } from './steps.mjs'

const OUT = process.argv[2]
const BASE = 'http://localhost:5181'
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe'
const PORT = 9333
const WIDTH = 1440
mkdirSync(OUT, { recursive: true })

const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${join(OUT, '..', 'chrome-profile')}`,
  '--no-first-run', '--hide-scrollbars', `--window-size=${WIDTH},900`, 'about:blank',
])
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

let targets = []
for (let i = 0; i < 50 && !targets.some((t) => t.type === 'page'); i++) {
  await sleep(200)
  targets = await fetch(`http://127.0.0.1:${PORT}/json`).then((r) => r.json(), () => [])
}
const ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl)
await new Promise((r) => ws.addEventListener('open', r))
let id = 0
const pending = new Map()
ws.addEventListener('message', (e) => {
  const msg = JSON.parse(e.data)
  const p = msg.id && pending.get(msg.id)
  if (!p) return
  pending.delete(msg.id)
  msg.error ? p.reject(new Error(JSON.stringify(msg.error))) : p.resolve(msg.result)
})
const cdp = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const n = ++id
    pending.set(n, { resolve, reject })
    ws.send(JSON.stringify({ id: n, method, params }))
  })
await cdp('Page.enable')
await cdp('Runtime.enable')

async function js(expression) {
  const r = await cdp('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })
  if (r.exceptionDetails) throw new Error(`${expression.slice(0, 120)} -> ${r.exceptionDetails.exception?.description}`)
  return r.result.value
}

async function size(height) {
  await cdp('Emulation.setDeviceMetricsOverride', { width: WIDTH, height, deviceScaleFactor: 1, mobile: false })
  await sleep(250)
}

async function go(path, user) {
  await size(900)
  await cdp('Page.navigate', { url: BASE + '/sign-in' })
  await sleep(600)
  await js(`sessionStorage.clear(); ${user ? `sessionStorage.setItem('seastock.session', '${user}')` : ''}`)
  await cdp('Page.navigate', { url: BASE + path })
  await sleep(900)
}

const HELPERS = `{
  const want = (el) => (el.textContent || '').replace(/\\s+/g, ' ').trim()
  window.__find = (text, sel, scope) => {
    const root = scope === 'dialog' ? document.querySelector('dialog[open]') : document
    const all = [...root.querySelectorAll(sel)].filter((el) => want(el) === text || want(el).startsWith(text))
    if (!all.length) throw new Error('not found: ' + text)
    return all[0]
  }
  window.__field = (label, scope) => {
    const root = scope === 'dialog' ? document.querySelector('dialog[open]') : document
    const l = [...root.querySelectorAll('label')].find((x) => want(x) === label)
    if (!l) throw new Error('no label: ' + label)
    return l.htmlFor ? document.getElementById(l.htmlFor) : l.querySelector('input,select,textarea')
  }
  window.__set = (el, value) => {
    const proto = el.tagName === 'SELECT' ? HTMLSelectElement : el.tagName === 'TEXTAREA' ? HTMLTextAreaElement : HTMLInputElement
    Object.getOwnPropertyDescriptor(proto.prototype, 'value').set.call(el, value)
    el.dispatchEvent(new Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }))
  }
  window.T = (text, sel = '*') => {
    const all = [...document.querySelectorAll(sel)].filter((el) => want(el) === text)
    if (!all.length) throw new Error('no element with text: ' + text)
    return all[all.length - 1]
  }
  window.C = (text, closest, sel) => T(text, sel).closest(closest)
  window.Q = (selector) => {
    const el = document.querySelector(selector)
    if (!el) throw new Error('no element: ' + selector)
    return el
  }
}`
const helpers = () => js(HELPERS)

async function click(text, scope = 'page', sel = 'button, a, [role=tab]') {
  await helpers()
  await js(`__find(${JSON.stringify(text)}, ${JSON.stringify(sel)}, ${JSON.stringify(scope)}).click()`)
  await sleep(500)
}
async function fill(label, value, scope = 'page') {
  await helpers()
  await js(`__set(__field(${JSON.stringify(label)}, ${JSON.stringify(scope)}), ${JSON.stringify(value)})`)
  await sleep(250)
}

const SHOTS = {}
/** full: grow the window to the page's scroll height so nothing is cut off. */
async function shot(name, { full = true, marks = [] } = {}) {
  if (full) {
    const h = await js(`(() => { const b = document.querySelector('main .overflow-y-auto'); return b ? b.scrollHeight + 72 : 900 })()`)
    await size(Math.max(900, Math.min(h + 10, 1900)))
  }
  await helpers()
  const boxes = []
  for (const [label, expr] of marks) {
    const r = await js(`(() => { const r = (${expr}).getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height } })()`)
    boxes.push({ label, ...r })
  }
  SHOTS[name] = { ...(await js('({ w: innerWidth, h: innerHeight })')), boxes }
  const { data } = await cdp('Page.captureScreenshot', { format: 'png' })
  writeFileSync(join(OUT, `${name}.png`), Buffer.from(data, 'base64'))
  console.log('saved', name, boxes.length, 'boxes')
  if (full) await size(900)
}

const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const ctx = { go, js, shot, click, fill, cdp, sleep, join, writeFileSync, OUT }
try {
  await new AsyncFunction('ctx', `with (ctx) {${steps}}`)(ctx)
} catch (e) {
  console.error('FAILED:', e.message)
  process.exitCode = 1
} finally {
  writeFileSync(join(OUT, 'shots.json'), JSON.stringify(SHOTS, null, 1))
  ws.close()
  chrome.kill()
}
