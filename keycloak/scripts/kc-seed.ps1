<#
.SYNOPSIS
  Creates the synthetic test users from seed-users.json in the local pixorex realm. Idempotent: existing users are
  left as they are. Use -Reset to delete and recreate them (restores invited/unverified states for testing).
#>
param([switch]$Reset)

. "$PSScriptRoot\kc-common.ps1"

$seed = Get-Content (Join-Path $PSScriptRoot 'seed-users.json') -Raw | ConvertFrom-Json
$realmRoles = @{}
foreach ($role in @(Invoke-KcAdmin -Path '/roles')) { $realmRoles[$role.name] = $role }

foreach ($u in $seed.users) {
    $existing = @(Invoke-KcAdmin -Path "/users?username=$($u.username)&exact=true") | Select-Object -First 1
    if ($existing -and $Reset) {
        Invoke-KcAdmin -Method Delete -Path "/users/$($existing.id)" | Out-Null
        $existing = $null
    }
    if ($existing) {
        Write-Host ("  exists   {0,-24} {1}" -f $u.email, $u.note)
        continue
    }

    $attributes = @{ app_user_id = @($u.username); tenant_id = @($seed.tenantId) }
    if ($u.phone) {
        $attributes.phone_number = @($u.phone)
        $attributes.phone_verified = @(([string]$u.phoneVerified).ToLower())
    }
    $body = @{
        username = $u.username; email = $u.email; firstName = $u.firstName; lastName = $u.lastName
        enabled = [bool]$u.enabled; emailVerified = [bool]$u.emailVerified; attributes = $attributes
    }
    Invoke-KcAdmin -Method Post -Path '/users' -Body $body | Out-Null
    $created = @(Invoke-KcAdmin -Path "/users?username=$($u.username)&exact=true")[0]

    $roles = @($u.roles | ForEach-Object { $r = $realmRoles[$_]; @{ id = $r.id; name = $r.name } })
    if ($roles.Count -gt 0) {
        Invoke-KcAdmin -Method Post -Path "/users/$($created.id)/role-mappings/realm" -Body $roles | Out-Null
    }
    Write-Host ("  created  {0,-24} {1}" -f $u.email, $u.note) -ForegroundColor Green
}
Write-Host "Seeded realm '$script:Realm' at $script:KcUrl. Codes arrive in Mailpit: $script:MailpitUrl"
