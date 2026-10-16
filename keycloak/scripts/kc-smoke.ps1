<#
.SYNOPSIS
  Headless end-to-end check of the local Keycloak: drives the real sign-in pages like a browser, reads codes from
  Mailpit, and checks tokens, channel rules, activation, lockout, throttling and audit events. Used locally and in CI.
  It recreates the synthetic users and clears their lockouts first. LOCAL / CI ONLY.
#>
param([switch]$SkipAudit)

. "$PSScriptRoot\kc-common.ps1"

$WebRedirect = 'http://localhost:5173/auth/callback'
$MobileRedirect = 'com.pixorex.mobile:/oauth2redirect'
$script:Passed = 0
$script:Failed = @()

function Check([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) { $script:Passed++; Write-Host "  PASS  $Name" -ForegroundColor Green }
    else { $script:Failed += $Name; Write-Host "  FAIL  $Name $Detail" -ForegroundColor Red }
}

# ---- a minimal browser: cookies, manual redirects inside Keycloak, HTML form posts ----

function New-Browser {
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    # Keycloak marks its cookies Secure; browsers still send them to http://localhost, .NET's CookieContainer does not.
    $handler.UseCookies = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    [pscustomobject]@{ Client = $client; Cookies = @{}; Html = ''; Location = $null }
}

function Update-Cookies($Browser, $Response) {
    $values = $null
    if (-not $Response.Headers.TryGetValues('Set-Cookie', [ref]$values)) { return }
    foreach ($header in $values) {
        $pair = ($header -split ';')[0]
        $name, $value = $pair -split '=', 2
        if ($header -match '(?i)max-age=0' -or [string]::IsNullOrEmpty($value)) { $Browser.Cookies.Remove($name.Trim()) }
        else { $Browser.Cookies[$name.Trim()] = $value }
    }
}

function Send-Browser($Browser, [string]$Url, [hashtable]$Form) {
    $Browser.Location = $null
    for ($hop = 0; $hop -lt 10; $hop++) {
        $method = if ($Form) { [System.Net.Http.HttpMethod]::Post } else { [System.Net.Http.HttpMethod]::Get }
        $request = New-Object System.Net.Http.HttpRequestMessage($method, $Url)
        if ($Browser.Cookies.Count -gt 0) {
            $request.Headers.TryAddWithoutValidation('Cookie', (($Browser.Cookies.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ')) | Out-Null
        }
        if ($Form) {
            $pairs = New-Object 'System.Collections.Generic.Dictionary[string,string]'
            foreach ($k in $Form.Keys) { $pairs.Add($k, [string]$Form[$k]) }
            $request.Content = New-Object System.Net.Http.FormUrlEncodedContent($pairs)
        }
        $response = $Browser.Client.SendAsync($request).Result
        Update-Cookies $Browser $response
        $Form = $null
        $status = [int]$response.StatusCode
        if ($status -ge 300 -and $status -lt 400) {
            $next = $response.Headers.Location.OriginalString
            if (-not $next.StartsWith('http')) { $next = (New-Object System.Uri((New-Object System.Uri($Url)), $next)).AbsoluteUri }
            if ($next.StartsWith($script:KcUrl)) { $Url = $next; continue }
            $Browser.Location = $next
            $Browser.Html = ''
            return
        }
        $Browser.Html = $response.Content.ReadAsStringAsync().Result
        return
    }
    throw "Too many redirects from $Url"
}

function Get-FormAction($Browser, [string]$FormId) {
    if ($Browser.Html -match "<form[^>]*id=`"$FormId`"[^>]*action=`"([^`"]+)`"") { return [System.Net.WebUtility]::HtmlDecode($Matches[1]) }
    return $null
}

function Get-PageTitle($Browser) {
    if ($Browser.Html -match '(?s)<h1 id="px-title"[^>]*>\s*(.*?)\s*</h1>') { return [System.Net.WebUtility]::HtmlDecode($Matches[1]).Trim() }
    return ''
}

function Get-Alert($Browser) {
    if ($Browser.Html -match '(?s)class="px-alert[^"]*"[^>]*>\s*(.*?)\s*</div>') { return [System.Net.WebUtility]::HtmlDecode($Matches[1]).Trim() }
    return ''
}

function Test-Form($Browser, [string]$FormId) { $null -ne (Get-FormAction $Browser $FormId) }

function Submit($Browser, [string]$FormId, [hashtable]$Fields) {
    $action = Get-FormAction $Browser $FormId
    if (-not $action) { throw "Form $FormId not on page '$(Get-PageTitle $Browser)'" }
    Send-Browser $Browser $action $Fields
}

function Start-SignIn([string]$ClientId, [string]$Redirect, [string]$LoginHint, [string]$Scope = 'openid profile email') {
    $browser = New-Browser
    $pkce = New-Pkce
    $browser | Add-Member -NotePropertyName Pkce -NotePropertyValue $pkce
    $browser | Add-Member -NotePropertyName ClientId -NotePropertyValue $ClientId
    $browser | Add-Member -NotePropertyName Redirect -NotePropertyValue $Redirect
    Send-Browser $browser (Get-AuthorizeUrl -ClientId $ClientId -RedirectUri $Redirect -Pkce $pkce -LoginHint $LoginHint -Scope $Scope)
    $browser
}

function Complete-SignIn($Browser) {
    if (-not $Browser.Location -or $Browser.Location -notmatch '[?&]code=([^&]+)') { return $null }
    $tokens = Invoke-TokenExchange -ClientId $Browser.ClientId -RedirectUri $Browser.Redirect -Code ([uri]::UnescapeDataString($Matches[1])) -Pkce $Browser.Pkce
    $claims = ConvertFrom-Jwt $tokens.access_token
    $claims | Add-Member -NotePropertyName px_refresh_typ -NotePropertyValue (ConvertFrom-Jwt $tokens.refresh_token).typ
    $claims
}

function Finish($Browser, [string]$Code) {
    Submit $Browser 'px-code-form' @{ code = $Code }
    Complete-SignIn $Browser
}

function Get-MessageCount([string]$To) { (Get-MailpitMessages $To).Count }

function Set-OtpConfig([hashtable]$Config) {
    $execution = @(Invoke-KcAdmin -Path '/authentication/flows/pixorex-browser-code/executions') | Where-Object { $_.providerId -eq 'pixorex-otp' }
    if ($execution.authenticationConfig) { Invoke-KcAdmin -Method Delete -Path "/authentication/config/$($execution.authenticationConfig)" | Out-Null }
    if ($Config) {
        Invoke-KcAdmin -Method Post -Path "/authentication/executions/$($execution.id)/config" -Body @{ alias = "pixorex-otp-smoke-$([guid]::NewGuid().ToString('N').Substring(0,8))"; config = $Config } | Out-Null
    }
}

function Get-BruteForce([string]$Email) {
    $user = Get-KcUser $Email
    Invoke-KcAdmin -Path "/attack-detection/brute-force/users/$($user.id)"
}

function Wait-BruteForce { Start-Sleep -Milliseconds 1300 }   # failures closer than quickLoginCheck (1 s) trigger a short quick-login lock

# ---------------------------------------------------------------------------------------------------------------

Write-Host "Keycloak smoke test against $script:KcUrl" -ForegroundColor Cyan
& "$PSScriptRoot\kc-seed.ps1" -Reset | Out-Null
Invoke-KcAdmin -Method Delete -Path '/attack-detection/brute-force/users' | Out-Null
# A fresh send-limit window per run, so repeated runs within 15 minutes do not trip the throttle.
Set-OtpConfig @{ sendWindowSeconds = [string](3600 + (Get-Random -Minimum 1 -Maximum 80000)) }
Clear-Mailpit
$seed = Get-Content (Join-Path $PSScriptRoot 'seed-users.json') -Raw | ConvertFrom-Json
$ids = @{}; foreach ($u in $seed.users) { $ids[$u.key] = $u.username }

try {
    Write-Host 'Discovery and grants'
    $discovery = Invoke-RestMethod "$script:KcUrl/realms/pixorex/.well-known/openid-configuration"
    Check 'issuer is the realm URL' ($discovery.issuer -eq "$script:KcUrl/realms/pixorex")
    foreach ($clientId in 'pixorex-web', 'pixorex-mobile') {
        $refused = $false
        try { Invoke-RestMethod -Method Post "$script:KcUrl/realms/pixorex/protocol/openid-connect/token" -Body @{ grant_type = 'password'; client_id = $clientId; username = 'ea@demo.local'; password = 'x' } | Out-Null }
        catch { $refused = $true }
        Check "password grant refused for $clientId" $refused
    }

    Write-Host 'Web dashboard (email only)'
    $b = Start-SignIn 'pixorex-web' $WebRedirect
    Check 'web shows the identifier page' (Test-Form $b 'px-identifier-form')
    Check 'web identifier page uses the Pixorex theme' ($b.Html -match 'pixorex\.css')
    Submit $b 'px-identifier-form' @{ identifier = 'EA@demo.local' }
    Check 'invited EA goes straight to the code page (email only)' (Test-Form $b 'px-code-form')
    $claims = Finish $b (Get-LatestCode 'ea@demo.local')
    Check 'EA gets tokens from the email code' ($null -ne $claims)
    if ($claims) {
        Check 'token has tenant_id' ($claims.tenant_id -eq $seed.tenantId)
        Check 'token has app_user_id' ($claims.app_user_id -eq $ids.ea)
        Check 'token audience includes pixorex-api' (@($claims.aud) -contains 'pixorex-api')
        Check 'token azp is pixorex-web' ($claims.azp -eq 'pixorex-web')
        Check 'token carries no roles' ($null -eq $claims.realm_access)
        Check 'web token has no phone_verified claim' ($null -eq $claims.phone_verified)
        Check 'web gets a normal (not offline) refresh token' ($claims.px_refresh_typ -eq 'Refresh')
    }
    Check 'first sign-in activated EA (emailVerified=true)' ((Get-KcUser 'ea@demo.local').emailVerified -eq $true)

    $b = Start-SignIn 'pixorex-web' $WebRedirect
    Submit $b 'px-identifier-form' @{ identifier = 'nobody@demo.local' }
    Check 'unknown email sees the same code page' (Test-Form $b 'px-code-form')
    Submit $b 'px-code-form' @{ code = '123456' }
    Check 'unknown email: any code is wrong' ((Get-Alert $b) -match 'not right')
    Start-Sleep -Seconds 1
    Check 'unknown email: nothing was sent' ((Get-MessageCount 'nobody@demo.local') -eq 0)

    $b = Start-SignIn 'pixorex-web' $WebRedirect
    Submit $b 'px-identifier-form' @{ identifier = 'gone@demo.local' }
    Check 'removed (disabled) user sees the code page' (Test-Form $b 'px-code-form')
    Check 'removed user: nothing was sent' ((Get-MessageCount 'gone@demo.local') -eq 0)

    $b = Start-SignIn 'pixorex-web' $WebRedirect
    Submit $b 'px-identifier-form' @{ identifier = 'tech1@demo.local' }
    Check 'technician on web is told to use the mobile app' ((Get-Alert $b) -match 'mobile app')
    Check 'technician on web: nothing was sent' ((Get-MessageCount 'tech1@demo.local') -eq 0)

    $b = Start-SignIn 'pixorex-web' $WebRedirect
    Submit $b 'px-identifier-form' @{ identifier = '+15550100001' }
    Check 'web refuses a phone number as identifier' ((Test-Form $b 'px-identifier-form') -and ((Get-Alert $b) -match 'valid email'))

    $b = Start-SignIn 'pixorex-web' $WebRedirect 'dual@demo.local'
    Check 'admin+technician on web: login_hint skips to the code page' (Test-Form $b 'px-code-form')
    Check 'admin+technician on web: email only' ($b.Html -match 'If this email belongs')
    Submit $b 'px-resend-form' @{ resend = '1' }
    Check 'resend within 60 s is refused' ((Get-Alert $b) -match 'wait')
    Check 'resend refusal sent nothing extra' ((Get-MessageCount 'dual@demo.local') -eq 1)

    Write-Host 'Mobile app (SMS or email)'
    $b = Start-SignIn 'pixorex-mobile' $MobileRedirect -Scope 'openid profile email offline_access'
    Submit $b 'px-identifier-form' @{ identifier = 'tech1@demo.local' }
    Check 'active technician gets the channel choice' (Test-Form $b 'px-channel-form')
    Check 'channel choice masks the phone' ($b.Html -match '0001' -and $b.Html -notmatch '5550100001')
    Submit $b 'px-channel-form' @{ channel = 'sms' }
    $smsTo = Get-SmsAddress '+15550100001'
    $claims = Finish $b (Get-LatestCode $smsTo)
    Check 'technician signs in with an SMS code' ($null -ne $claims)
    if ($claims) {
        Check 'mobile token azp is pixorex-mobile' ($claims.azp -eq 'pixorex-mobile')
        Check 'mobile token has phone_verified=true' ($claims.phone_verified -eq $true)
        Check 'mobile gets an offline refresh token (offline_access)' ($claims.px_refresh_typ -eq 'Offline')
    }
    $sms = Invoke-RestMethod "$script:MailpitUrl/api/v1/message/$((Get-MailpitMessages $smsTo)[0].ID)"
    Check 'SMS text has the autofill line' ($sms.Text -match '@localhost #\d{6}')

    $b = Start-SignIn 'pixorex-mobile' $MobileRedirect
    Submit $b 'px-identifier-form' @{ identifier = '+1 (555) 010-0001' }
    Check 'mobile accepts a verified phone number as identifier' (Test-Form $b 'px-channel-form')
    Submit $b 'px-channel-form' @{ channel = 'email' }
    $claims = Finish $b (Get-LatestCode 'tech1@demo.local')
    Check 'phone identifier + email code signs in' ($claims.app_user_id -eq $ids.tech1)

    $b = Start-SignIn 'pixorex-mobile' $MobileRedirect 'tech2@demo.local'
    Check 'invited technician: login_hint goes straight to the code page (SMS only)' ((Test-Form $b 'px-code-form') -and ($b.Html -match 'If this number belongs'))
    $claims = Finish $b (Get-LatestCode (Get-SmsAddress '+15550100002'))
    Check 'invited technician signs in with the SMS code' ($null -ne $claims)
    Check 'invited technician is activated (phone_verified=true)' ((Get-KcUser 'tech2@demo.local').attributes.phone_verified[0] -eq 'true')

    $b = Start-SignIn 'pixorex-mobile' $MobileRedirect
    Submit $b 'px-identifier-form' @{ identifier = 'buadmin.p04@demo.local' }
    Check 'admin on mobile is told to use the web dashboard' ((Get-Alert $b) -match 'web dashboard')

    Write-Host 'Lockout (5 wrong codes, 30 minutes)'
    $b = Start-SignIn 'pixorex-web' $WebRedirect
    Submit $b 'px-identifier-form' @{ identifier = 'buadmin.p04@demo.local' }
    for ($i = 1; $i -le 4; $i++) { Submit $b 'px-code-form' @{ code = '000000' }; Wait-BruteForce }
    Check '4 wrong codes show the wrong-code message' ((Get-Alert $b) -match 'not right')
    Check '4 wrong codes are counted' ((Get-BruteForce 'buadmin.p04@demo.local').numFailures -eq 4)
    $claims = Finish $b (Get-LatestCode 'buadmin.p04@demo.local')
    Check '4 wrong then the right code signs in' ($null -ne $claims)
    Wait-BruteForce
    Check 'success resets the failure count' ((Get-BruteForce 'buadmin.p04@demo.local').numFailures -eq 0)

    $b = Start-SignIn 'pixorex-mobile' $MobileRedirect
    Submit $b 'px-identifier-form' @{ identifier = 'dual@demo.local' }
    Submit $b 'px-channel-form' @{ channel = 'email' }
    for ($i = 1; $i -le 5; $i++) { Submit $b 'px-code-form' @{ code = '000000' }; Wait-BruteForce }
    Check '5th wrong code shows the locked page' ((Get-PageTitle $b) -match 'locked' -and (Get-Alert $b) -match '30 minutes')
    Check 'attack detection reports the user disabled' ((Get-BruteForce 'dual@demo.local').disabled -eq $true)
    $before = Get-MessageCount 'dual@demo.local'
    $b = Start-SignIn 'pixorex-web' $WebRedirect
    Submit $b 'px-identifier-form' @{ identifier = 'dual@demo.local' }
    Check 'locked user gets the locked page on a new sign-in' ((Get-PageTitle $b) -match 'locked')
    Check 'locked user: nothing was sent' ((Get-MessageCount 'dual@demo.local') -eq $before)
    Invoke-KcAdmin -Method Delete -Path "/attack-detection/brute-force/users/$((Get-KcUser 'dual@demo.local').id)" | Out-Null

    Write-Host 'Send limit (5 codes per 15 minutes)'
    Set-OtpConfig @{ sendWindowSeconds = [string](3600 + (Get-Random -Minimum 1 -Maximum 80000)) }
    $sent = 0
    for ($i = 1; $i -le 6; $i++) {
        $b = Start-SignIn 'pixorex-web' $WebRedirect 'ea@demo.local'
        if ((Get-Alert $b) -match 'Too many codes') { break }
        $sent++
    }
    Check 'the 6th code request in the window is refused' ($sent -eq 5) "sent=$sent"

    if (-not $SkipAudit) {
        Write-Host 'Audit events'
        $events = @(Invoke-KcAdmin -Path "/events?type=LOGIN&user=$((Get-KcUser 'ea@demo.local').id)")
        Check 'Keycloak stored the LOGIN event with activation=true' (@($events | Where-Object { $_.details.activation -eq 'true' }).Count -ge 1)
        $errors = @(Invoke-KcAdmin -Path "/events?type=LOGIN_ERROR&user=$((Get-KcUser 'buadmin.p04@demo.local').id)")
        Check 'wrong codes are stored as LOGIN_ERROR' ($errors.Count -ge 4)
        Start-Sleep -Seconds 2
        $sink = (docker compose --project-directory $script:RepoRoot logs --no-color event-sink 2>$null) -join "`n"
        Check 'event-sink received a signed LOGIN event' (($sink -match '"type":\s*"LOGIN"') -and ($sink -match 'x-pixorex-signature') -and ($sink -match $ids.ea))
        Check 'event-sink never received a code or token' ($sink -notmatch '"code":' -and $sink -notmatch 'access_token')
    }
}
finally {
    Set-OtpConfig $null
    Invoke-KcAdmin -Method Delete -Path '/attack-detection/brute-force/users' | Out-Null
}

Write-Host ''
if ($script:Failed.Count -eq 0) {
    Write-Host "All $script:Passed checks passed." -ForegroundColor Green
    exit 0
}
Write-Host "$($script:Failed.Count) failed, $script:Passed passed:" -ForegroundColor Red
$script:Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
exit 1
