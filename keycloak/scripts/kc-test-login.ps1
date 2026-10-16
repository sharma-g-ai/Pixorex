<#
.SYNOPSIS
  Interactive PKCE sign-in without any app. Opens your browser on the Pixorex sign-in page, catches the redirect on a
  temporary loopback URL, exchanges the code and prints the token claims.

.DESCRIPTION
  The loopback redirect http://localhost:53682/callback is added to the client in your LOCAL Keycloak only for the
  duration of the script and removed afterwards. It is never part of realm-pixorex.json.

.EXAMPLE
  .\keycloak\scripts\kc.ps1 login web
  .\keycloak\scripts\kc.ps1 login mobile
  .\keycloak\scripts\kc-test-login.ps1 -Client mobile -LoginHint tech2@demo.local
#>
param(
    [ValidateSet('web', 'mobile')][string]$Client = 'web',
    [string]$LoginHint,
    [int]$TimeoutSeconds = 300
)

. "$PSScriptRoot\kc-common.ps1"

$clientId = "pixorex-$Client"
$redirect = 'http://localhost:53682/callback'
$scope = if ($Client -eq 'mobile') { 'openid profile email offline_access' } else { 'openid profile email' }

$clientRep = @(Invoke-KcAdmin -Path "/clients?clientId=$clientId")[0]
$originalRedirects = @($clientRep.redirectUris)
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://localhost:53682/')

try {
    $clientRep.redirectUris = @($originalRedirects + $redirect | Select-Object -Unique)
    Invoke-KcAdmin -Method Put -Path "/clients/$($clientRep.id)" -Body $clientRep | Out-Null
    $listener.Start()

    $pkce = New-Pkce
    $url = Get-AuthorizeUrl -ClientId $clientId -RedirectUri $redirect -Pkce $pkce -Scope $scope -LoginHint $LoginHint
    Write-Host "Signing in to $clientId. Codes arrive in Mailpit: $script:MailpitUrl" -ForegroundColor Cyan
    Write-Host "If the browser does not open, paste this URL:`n  $url"
    if ($IsWindows -or $env:OS -eq 'Windows_NT') { Start-Process $url }

    $pending = $listener.BeginGetContext($null, $null)
    if (-not $pending.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) { throw "No sign-in completed within $TimeoutSeconds s" }
    $context = $listener.EndGetContext($pending)
    $query = [System.Web.HttpUtility]::ParseQueryString($context.Request.Url.Query)
    $html = [Text.Encoding]::UTF8.GetBytes('<html><body style="font-family:sans-serif"><h2>Signed in. You can close this tab.</h2></body></html>')
    $context.Response.ContentType = 'text/html; charset=utf-8'
    $context.Response.OutputStream.Write($html, 0, $html.Length)
    $context.Response.Close()

    if ($query['state'] -ne $pkce.State) { throw 'State mismatch: the redirect did not come from this sign-in' }
    if ($query['error']) { throw "Keycloak returned error '$($query['error'])': $($query['error_description'])" }

    $tokens = Invoke-TokenExchange -ClientId $clientId -RedirectUri $redirect -Code $query['code'] -Pkce $pkce
    $access = ConvertFrom-Jwt $tokens.access_token
    $id = ConvertFrom-Jwt $tokens.id_token

    Write-Host "`nAccess token claims the API uses:" -ForegroundColor Green
    [pscustomobject]@{
        iss = $access.iss; aud = (@($access.aud) -join ', '); azp = $access.azp; sub = $access.sub; sid = $access.sid
        tenant_id = $access.tenant_id; app_user_id = $access.app_user_id
        email_verified = $access.email_verified; phone_verified = $access.phone_verified
        expires_in = $tokens.expires_in; refresh_type = $(if ($tokens.refresh_token) { (ConvertFrom-Jwt $tokens.refresh_token).typ } else { '' })
    } | Format-List
    Write-Host 'ID token:' -ForegroundColor Green
    [pscustomobject]@{ email = $id.email; name = $id.name; tenant_id = $id.tenant_id; app_user_id = $id.app_user_id } | Format-List
}
finally {
    if ($listener.IsListening) { $listener.Stop() }
    $clientRep.redirectUris = $originalRedirects
    Invoke-KcAdmin -Method Put -Path "/clients/$($clientRep.id)" -Body $clientRep | Out-Null
}
