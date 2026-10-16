# Shared helpers for the local Keycloak scripts. Dot-source it: . "$PSScriptRoot\kc-common.ps1"
# Works in Windows PowerShell 5.1 and PowerShell 7 (CI runs pwsh on Linux).

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:Realm = 'pixorex'

# Same defaults as docker-compose.yml; a local .env (git-ignored) may override them.
$script:KcEnv = @{ KC_HTTP_PORT = '8080'; KC_MGMT_PORT = '9100'; KC_ADMIN_USER = 'admin'; KC_ADMIN_PASSWORD = 'local-only' }
$envFile = Join-Path $script:RepoRoot '.env'
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*(KC_HTTP_PORT|KC_MGMT_PORT|KC_ADMIN_USER|KC_ADMIN_PASSWORD)\s*=\s*(\S+)\s*$') { $script:KcEnv[$Matches[1]] = $Matches[2] }
    }
}
$script:KcUrl = "http://localhost:$($script:KcEnv.KC_HTTP_PORT)"
$script:KcMgmtUrl = "http://localhost:$($script:KcEnv.KC_MGMT_PORT)"
$script:MailpitUrl = 'http://localhost:8025'

function Get-AdminToken {
    $body = @{ grant_type = 'password'; client_id = 'admin-cli'; username = $script:KcEnv.KC_ADMIN_USER; password = $script:KcEnv.KC_ADMIN_PASSWORD }
    (Invoke-RestMethod -Method Post "$script:KcUrl/realms/master/protocol/openid-connect/token" -Body $body).access_token
}

function Invoke-KcAdmin {
    param([string]$Method = 'Get', [string]$Path, $Body)
    if (-not $script:AdminToken) { $script:AdminToken = Get-AdminToken }
    $params = @{ Method = $Method; Uri = "$script:KcUrl/admin/realms/$script:Realm$Path"; Headers = @{ Authorization = "Bearer $script:AdminToken" } }
    # -InputObject keeps a one-element array as a JSON array (piping would unwrap it).
    if ($null -ne $Body) { $params.Body = (ConvertTo-Json -InputObject $Body -Depth 10); $params.ContentType = 'application/json' }
    # Windows PowerShell 5.1 emits a JSON array as one object; piping unrolls it so @(...) sees the elements.
    Invoke-RestMethod @params | ForEach-Object { $_ }
}

function Get-KcUser([string]$Email) {
    @(Invoke-KcAdmin -Path "/users?email=$([uri]::EscapeDataString($Email))&exact=true") | Select-Object -First 1
}

function ConvertTo-Base64Url([byte[]]$Bytes) {
    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-Pkce {
    $bytes = New-Object byte[] 48
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $verifier = ConvertTo-Base64Url $bytes
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $challenge = ConvertTo-Base64Url ($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($verifier)))
    [pscustomobject]@{ Verifier = $verifier; Challenge = $challenge; State = [guid]::NewGuid().ToString('N') }
}

function Get-AuthorizeUrl {
    param([string]$ClientId, [string]$RedirectUri, $Pkce, [string]$Scope = 'openid profile email', [string]$LoginHint)
    $q = "client_id=$ClientId&response_type=code&scope=$([uri]::EscapeDataString($Scope))&redirect_uri=$([uri]::EscapeDataString($RedirectUri))" +
         "&code_challenge=$($Pkce.Challenge)&code_challenge_method=S256&state=$($Pkce.State)"
    if ($LoginHint) { $q += "&login_hint=$([uri]::EscapeDataString($LoginHint))" }
    "$script:KcUrl/realms/$script:Realm/protocol/openid-connect/auth?$q"
}

function Invoke-TokenExchange {
    param([string]$ClientId, [string]$RedirectUri, [string]$Code, $Pkce)
    $body = @{ grant_type = 'authorization_code'; client_id = $ClientId; code = $Code; redirect_uri = $RedirectUri; code_verifier = $Pkce.Verifier }
    Invoke-RestMethod -Method Post "$script:KcUrl/realms/$script:Realm/protocol/openid-connect/token" -Body $body
}

function ConvertFrom-Jwt([string]$Jwt) {
    $part = $Jwt.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($part.Length % 4) { 2 { $part += '==' } 3 { $part += '=' } }
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part)) | ConvertFrom-Json
}

# ---- Mailpit (local inbox for email and SMS codes) ----

function Clear-Mailpit { Invoke-RestMethod -Method Delete "$script:MailpitUrl/api/v1/messages" | Out-Null }

function Get-MailpitMessages([string]$To) {
    $query = [uri]::EscapeDataString('to:"' + $To + '"')
    $result = Invoke-RestMethod "$script:MailpitUrl/api/v1/search?query=$query"
    # The leading comma stops PowerShell unrolling a one-item array (Windows PowerShell 5.1 objects have no .Count).
    , @($result.messages)
}

function Get-LatestCode {
    param([string]$To, [int]$TimeoutSeconds = 15)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $messages = Get-MailpitMessages $To
        if ($messages.Count -gt 0) {
            $message = Invoke-RestMethod "$script:MailpitUrl/api/v1/message/$($messages[0].ID)"
            if ($message.Text -match '(?<!\d)(\d{6})(?!\d)') { return $Matches[1] }
        }
        Start-Sleep -Milliseconds 500
    }
    throw "No code arrived in Mailpit for $To within $TimeoutSeconds s"
}

function Get-SmsAddress([string]$Phone) { 'sms+' + ($Phone -replace '\D', '') + '@pixorex.local' }
