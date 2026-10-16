<#
.SYNOPSIS
  Local Keycloak helper for Windows (replaces the Makefile targets). Synthetic data only.
  Works from any folder: it always runs against the repo root.

.EXAMPLE
  .\keycloak\scripts\kc.ps1 up
  .\keycloak\scripts\kc.ps1 build
  .\keycloak\scripts\kc.ps1 seed
  .\keycloak\scripts\kc.ps1 login web
  .\keycloak\scripts\kc.ps1 smoke
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('up', 'down', 'status', 'logs', 'restart', 'reset', 'export', 'build', 'seed', 'login', 'codes', 'smoke', 'help')]
    [string]$Command = 'help',

    [Parameter(Position = 1)]
    [string]$Target
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $RepoRoot

$Services = @('keycloak-db', 'mailpit', 'event-sink', 'keycloak')
$KcDataVolume = 'pixorex_kcdata'

# Same defaults as docker-compose.yml; a local .env (git-ignored) may override them.
$EnvValues = @{ KC_HTTP_PORT = '8080'; KC_MGMT_PORT = '9100' }
$EnvFile = Join-Path $RepoRoot '.env'
if (Test-Path $EnvFile) {
    foreach ($line in Get-Content $EnvFile) {
        if ($line -match '^\s*(KC_HTTP_PORT|KC_MGMT_PORT)\s*=\s*(\S+)\s*$') { $EnvValues[$Matches[1]] = $Matches[2] }
    }
}
$KcUrl = "http://localhost:$($EnvValues.KC_HTTP_PORT)"
$KcMgmtUrl = "http://localhost:$($EnvValues.KC_MGMT_PORT)"

function Wait-KeycloakReady {
    param([int]$TimeoutSeconds = 240)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    Write-Host "Waiting for Keycloak to become ready on $KcMgmtUrl/health/ready ..."
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-RestMethod -Uri "$KcMgmtUrl/health/ready" -TimeoutSec 5
            if ($r.status -eq 'UP') {
                Write-Host 'Keycloak is ready.' -ForegroundColor Green
                Write-Host "  Admin console : $KcUrl/admin  (local-only credentials in docker-compose.yml)"
                Write-Host "  Realm         : $KcUrl/realms/pixorex/.well-known/openid-configuration"
                Write-Host '  Mailpit inbox : http://localhost:8025   (email and SMS codes)'
                Write-Host '  Audit events  : docker compose logs -f event-sink'
                return
            }
        } catch { }
        Start-Sleep -Seconds 5
    }
    throw "Keycloak was not ready after $TimeoutSeconds seconds. Run: .\keycloak\scripts\kc.ps1 logs"
}

function Build-Spi {
    $spiDir = Join-Path $RepoRoot 'keycloak\spi'
    $m2 = Join-Path $env:USERPROFILE '.m2'
    New-Item -ItemType Directory -Force -Path $m2 | Out-Null
    docker run --rm -v "${spiDir}:/src" -v "${m2}:/root/.m2" -w /src maven:3.9-eclipse-temurin-21 mvn -B -q package
    if ($LASTEXITCODE -ne 0) { throw 'SPI build or unit tests failed.' }
    Copy-Item (Join-Path $spiDir 'target\pixorex-keycloak-spi.jar') (Join-Path $RepoRoot 'keycloak\providers\') -Force
    Write-Host 'Copied pixorex-keycloak-spi.jar to keycloak\providers\.'
}

function Assert-ProviderJar {
    if (-not (Test-Path (Join-Path $RepoRoot 'keycloak\providers\pixorex-keycloak-spi.jar'))) {
        Write-Host 'The sign-in plugin is not built yet (the realm needs it). Building it first ...' -ForegroundColor Yellow
        Build-Spi
    }
}

switch ($Command) {
    'up' {
        Assert-ProviderJar
        docker compose up -d @Services
        Wait-KeycloakReady
    }
    'down' {
        docker compose stop @Services
    }
    'status' {
        docker compose ps @Services
    }
    'logs' {
        docker compose logs -f keycloak
    }
    'restart' {
        docker compose restart keycloak
        Wait-KeycloakReady
    }
    'reset' {
        # --import-realm skips a realm that already exists, so a realm JSON change needs a fresh Keycloak database.
        Assert-ProviderJar
        docker compose rm -sf keycloak keycloak-db
        docker volume rm -f $KcDataVolume | Out-Null
        docker compose up -d @Services
        Wait-KeycloakReady
    }
    'export' {
        $exportDir = Join-Path $RepoRoot 'keycloak\export'
        New-Item -ItemType Directory -Force -Path $exportDir | Out-Null
        docker compose run --rm --no-deps -v "${exportDir}:/export" keycloak `
            export --realm pixorex --users skip --file /export/realm-pixorex.json
        Write-Host "Exported to keycloak\export\realm-pixorex.json. Review the diff and remove secrets before copying it to keycloak\realm\."
    }
    'build' {
        Build-Spi
        Write-Host 'Restarting Keycloak ...'
        docker compose restart keycloak
        Wait-KeycloakReady
    }
    'seed' {
        & (Join-Path $PSScriptRoot 'kc-seed.ps1') -Reset:($Target -eq 'reset')
    }
    'login' {
        $client = if ($Target) { $Target } else { 'web' }
        & (Join-Path $PSScriptRoot 'kc-test-login.ps1') -Client $client
    }
    'codes' {
        $result = Invoke-RestMethod 'http://localhost:8025/api/v1/messages?limit=10'
        foreach ($m in @($result.messages)) {
            $code = if ($m.Snippet -match '(?<!\d)(\d{6})(?!\d)') { $Matches[1] } else { '-' }
            $to = (@($m.To) | ForEach-Object { $_.Address }) -join ','
            Write-Host ('{0,-8} {1,-38} {2}' -f $code, $to, $m.Created)
        }
    }
    'smoke' {
        & (Join-Path $PSScriptRoot 'kc-smoke.ps1')
        exit $LASTEXITCODE
    }
    default {
        Write-Host 'Usage: .\keycloak\scripts\kc.ps1 <command> [target]'
        Write-Host '  up              start Keycloak, its database, Mailpit and the audit event sink'
        Write-Host '  down | status | logs | restart'
        Write-Host '  reset           wipe the Keycloak database and re-import keycloak\realm\realm-pixorex.json'
        Write-Host '  export          export the running realm to keycloak\export\ (to review console changes)'
        Write-Host '  build           build the sign-in plugin in Docker (runs unit tests) and restart Keycloak'
        Write-Host '  seed [reset]    create the synthetic test users (reset = recreate them as new)'
        Write-Host '  login web|mobile  sign in through the real pages in your browser and print the token claims'
        Write-Host '  codes           show the latest codes in Mailpit'
        Write-Host '  smoke           run the headless end-to-end checks'
    }
}
