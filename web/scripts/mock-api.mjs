// DEV ONLY: serves every contract slice as one mock API on :4010 until the real API exists.
// Delete this file and the "api:mock" script in package.json once the backend is running.
//
// Each slice is bundled on its own with all $refs inlined, then the paths are merged
// into one spec in the OS temp folder (nothing is written into the repo).
import { execFileSync, spawn } from 'node:child_process'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const REDOCLY = '@redocly/cli@2.57.0'
const PRISM = '@stoplight/prism-cli@5.15.11'
const PORT = process.env.MOCK_PORT ?? '4010'
const slices = [
  'slice-s2-auth-rbac',
  'slice-s3-capture-extraction',
  'slice-s4-workflow-review',
  'slice-s5-portal-export',
]
const shell = process.platform === 'win32'
const outDir = join(tmpdir(), 'pixorex-mock')
mkdirSync(outDir, { recursive: true })

const specs = slices.map((slice) => {
  const out = join(outDir, `${slice}.json`)
  execFileSync(
    'npx',
    [
      '-y',
      REDOCLY,
      'bundle',
      `../contracts/${slice}.yaml`,
      '--dereferenced',
      '--ext',
      'json',
      '-o',
      out,
    ],
    { stdio: ['ignore', 'ignore', 'inherit'], shell },
  )
  return JSON.parse(readFileSync(out, 'utf8'))
})

const [first, ...rest] = specs
const merged = {
  ...first,
  info: { ...first.info, title: 'Pixorex V1 (all slices, mock)' },
  paths: Object.assign({}, ...specs.map((s) => s.paths)),
  components: {
    securitySchemes: Object.assign({}, ...specs.map((s) => s.components?.securitySchemes ?? {})),
  },
}
const allFile = join(outDir, 'all.json')
writeFileSync(allFile, JSON.stringify(merged))
console.log(`Mock API: ${Object.keys(merged.paths).length} paths from ${rest.length + 1} slices`)

spawn('npx', ['-y', PRISM, 'mock', allFile, '--port', PORT], { stdio: 'inherit', shell })
