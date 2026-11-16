<#
.SYNOPSIS
  Adds sign-in accounts for the demo technicians made by api/scripts/seed_review_queue.py.
  Local Keycloak only. Safe to run twice: accounts that already exist are left alone.
.DESCRIPTION
  Each technician gets the mobile role. Codes arrive in Mailpit (http://localhost:8025).
  Run seed_review_queue.py first, so the same ids exist in the database.
.EXAMPLE
  powershell -File keycloak\scripts\kc-seed-technicians.ps1
#>
. "$PSScriptRoot\kc-common.ps1"

$tenant = '7e1d2c3b-0000-4000-8000-00000000a001'
$people = @(
    @{ id = '7e1d2c3b-0000-4000-8000-000000000030'; email = 'tara.demo@demo.local';  first = 'Tara';  last = 'Demo' }
    @{ id = '7e1d2c3b-0000-4000-8000-000000000031'; email = 'rohan.demo@demo.local'; first = 'Rohan'; last = 'Demo' }
    @{ id = '7e1d2c3b-0000-4000-8000-000000000032'; email = 'meera.demo@demo.local'; first = 'Meera'; last = 'Demo' }
    @{ id = '7e1d2c3b-0000-4000-8000-000000000033'; email = 'priya.demo@demo.local'; first = 'Priya'; last = 'Demo' }
    @{ id = '7e1d2c3b-0000-4000-8000-000000000034'; email = 'karan.demo@demo.local'; first = 'Karan'; last = 'Demo' }
    @{ id = '7e1d2c3b-0000-4000-8000-000000000035'; email = 'sana.demo@demo.local';  first = 'Sana';  last = 'Demo' }
)

$role = @(Invoke-KcAdmin -Path '/roles') | Where-Object { $_.name -eq 'pixorex-mobile' }
foreach ($p in $people) {
    if (@(Invoke-KcAdmin -Path "/users?username=$($p.id)&exact=true").Count -gt 0) {
        Write-Host ("  exists   {0}" -f $p.email)
        continue
    }
    $body = @{
        username = $p.id; email = $p.email; firstName = $p.first; lastName = $p.last
        enabled = $true; emailVerified = $true
        attributes = @{ app_user_id = @($p.id); tenant_id = @($tenant) }
    }
    Invoke-KcAdmin -Method Post -Path '/users' -Body $body | Out-Null
    $created = @(Invoke-KcAdmin -Path "/users?username=$($p.id)&exact=true")[0]
    Invoke-KcAdmin -Method Post -Path "/users/$($created.id)/role-mappings/realm" -Body @(@{ id = $role.id; name = $role.name }) | Out-Null
    Write-Host ("  created  {0}" -f $p.email) -ForegroundColor Green
}
Write-Host "Done. Sign in on the phone with the email; the code arrives in Mailpit: $script:MailpitUrl"
