<#
.SYNOPSIS
  One-command local setup: database, API, Keycloak with test users, web app. Synthetic data only.
  Safe to run again at any time: every step skips what already exists.

.EXAMPLE
  .\scripts\setup-local.ps1
  Then: cd web; npm run dev   and open http://localhost:5173

.NOTES
  Needs Docker Desktop (running) and Node 24. Local-only values; deployed environments use Vault.
  Real email (optional): put the PIXOREX_SMTP_* values in .env (see .env.example) and run this
  again; Keycloak's sign-in codes and the API's invites then go to real inboxes, not Mailpit.
#>
$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $Root

function Step([string]$Text) { Write-Host "`n== $Text" -ForegroundColor Cyan }

# Reads .env into a table (KEY=value lines only).
function Read-DotEnv {
    $values = [ordered]@{}
    if (Test-Path .env) {
        foreach ($line in Get-Content .env) {
            if ($line -match '^\s*([A-Z0-9_]+)\s*=(.*)$') { $values[$Matches[1]] = $Matches[2].Trim() }
        }
    }
    $values
}

# Sets one KEY=value in .env, replacing an existing line or appending.
function Set-DotEnv([string]$Key, [string]$Value) {
    $lines = @(if (Test-Path .env) { Get-Content .env })
    $found = $false
    $lines = $lines | ForEach-Object { if ($_ -match "^\s*$Key\s*=") { $found = $true; "$Key=$Value" } else { $_ } }
    if (-not $found) { $lines += "$Key=$Value" }
    Set-Content -Path .env -Value $lines -Encoding ascii
}

Step 'Checking Docker and Node'
docker info --format '{{.ServerVersion}}' *> $null
if ($LASTEXITCODE -ne 0) { throw 'Docker is not running. Start Docker Desktop and run this again.' }
$node = (node --version) 2>$null
if (-not $node) { throw 'Node is not installed. Install Node 24 LTS and run this again.' }
Write-Host "Docker OK, Node $node"

Step 'Keycloak (builds the sign-in plugin the first time, a few minutes)'
& (Join-Path $Root 'keycloak\scripts\kc.ps1') up

Step 'Database, migrations and API'
docker compose up -d --build
if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed. See the messages above.' }

Step 'Demo data (database)'
docker compose run --rm migrate python scripts/seed_synthetic.py
if ($LASTEXITCODE -ne 0) { throw 'Seeding the database failed.' }

Step 'Demo users (Keycloak)'
& (Join-Path $Root 'keycloak\scripts\kc.ps1') seed

Step 'API access to Keycloak (secret saved in .env, never printed)'
. (Join-Path $Root 'keycloak\scripts\kc-common.ps1')
$client = @(Invoke-KcAdmin -Path '/clients?clientId=pixorex-api-admin')[0]
$secret = (Invoke-KcAdmin -Path "/clients/$($client.id)/client-secret").value
Set-DotEnv 'PIXOREX_KEYCLOAK_ADMIN_SECRET' $secret
Write-Host '.env updated (git-ignored).'

$envValues = Read-DotEnv
if ($envValues['PIXOREX_SMTP_HOST'] -and $envValues['PIXOREX_SMTP_HOST'] -ne 'mailpit') {
    Step "Real email: Keycloak sends codes through $($envValues['PIXOREX_SMTP_HOST'])"
    $smtp = @{
        host = $envValues['PIXOREX_SMTP_HOST']; port = $envValues['PIXOREX_SMTP_PORT']
        from = $envValues['PIXOREX_SMTP_FROM']; fromDisplayName = $(if ($envValues['PIXOREX_SMTP_FROM_NAME']) { $envValues['PIXOREX_SMTP_FROM_NAME'] } else { 'Pixorex' })
        auth = 'true'; user = $envValues['PIXOREX_SMTP_USER']; password = $envValues['PIXOREX_SMTP_PASSWORD']
        starttls = $(if ($envValues['PIXOREX_SMTP_STARTTLS'] -eq 'true') { 'true' } else { 'false' }); ssl = 'false'
    }
    Invoke-KcAdmin -Method Put -Path '' -Body @{ smtpServer = $smtp } | Out-Null
} else {
    Step 'Local email: Keycloak sends codes to Mailpit'
    # Same values as keycloak/realm/realm-pixorex.json; also undoes an earlier real-email setup.
    $smtp = @{ host = 'mailpit'; port = '1025'; from = 'no-reply@pixorex.local'; fromDisplayName = 'Pixorex'
               auth = 'false'; starttls = 'false'; ssl = 'false' }
    Invoke-KcAdmin -Method Put -Path '' -Body @{ smtpServer = $smtp } | Out-Null
    Write-Host 'Codes and invites arrive in Mailpit (http://localhost:8025).'
}

Step 'Restarting the API with the .env values'
docker compose up -d api
if ($LASTEXITCODE -ne 0) { throw 'Restarting the API failed.' }

Step 'Web app'
Push-Location web
try {
    if (-not (Test-Path node_modules)) { npm ci; if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' } }
    if (-not (Test-Path .env.development.local)) {
        Set-Content -Path .env.development.local -Encoding ascii -Value @(
            '# Local only (git-ignored): npm run dev signs in with the local Keycloak.',
            'VITE_OIDC_AUTHORITY=http://localhost:8080/realms/pixorex',
            'VITE_OIDC_CLIENT_ID=pixorex-web')
    }
} finally { Pop-Location }

Step 'Checking everything is up'
$ready = $null
for ($i = 0; $i -lt 30 -and -not $ready; $i++) {
    try { $ready = Invoke-RestMethod http://localhost:8000/api/v1/ready -TimeoutSec 3 } catch { Start-Sleep -Seconds 2 }
}
if (-not $ready) { throw 'The API is not ready. Run: docker compose logs api' }
Write-Host 'API ready: database, Keycloak, MinIO and Vault all OK.' -ForegroundColor Green

Write-Host @'

Done. Start the web app:
    cd web
    npm run dev
Open http://localhost:5173 and sign in as:
    ea@demo.local            Enterprise Admin (Demo Coatings)
    buadmin.p04@demo.local   BU Admin, Plant 04
The 6-digit code is in Mailpit: http://localhost:8025
'@
if ($envValues['PIXOREX_SMTP_HOST'] -and $envValues['PIXOREX_SMTP_HOST'] -ne 'mailpit') {
    Write-Host 'Real email is on: *@demo.local codes stay in Mailpit; real invited addresses go to SendGrid.' -ForegroundColor Yellow
}
