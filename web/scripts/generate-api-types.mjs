// Regenerates the TypeScript API types from the OpenAPI contracts in ../contracts.
// Run after any contract change: npm run api:types
import { execFileSync } from 'node:child_process'

const files = {
  common: 'common',
  s2: 'slice-s2-auth-rbac',
  s3: 'slice-s3-capture-extraction',
  s4: 'slice-s4-workflow-review',
  s5: 'slice-s5-portal-export',
}

for (const [name, file] of Object.entries(files)) {
  execFileSync(
    'npx',
    ['openapi-typescript', `../contracts/${file}.yaml`, '-o', `src/api/generated/${name}.ts`],
    { stdio: 'inherit', shell: process.platform === 'win32' },
  )
}
