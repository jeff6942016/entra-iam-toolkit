# Disable-User.ps1
# Offboards a user (the "leaver" in joiner-mover-leaver):
#   1. Disables the account
#   2. Revokes all active sessions / refresh tokens
#   3. Removes all group memberships
# It does NOT delete the object. Real leaver processes retain the account for a
# period so mailbox/file access can be reassigned and audit history survives;
# deletion is a separate, later, deliberate step.
#
# Usage:   ./Disable-User.ps1 -UserPrincipalName "user@tenant.onmicrosoft.com"
# Scopes:  User.ReadWrite.All, Group.ReadWrite.All
# Module:  Install-Module Microsoft.Graph.Users.Actions -Scope CurrentUser  (first run)
#
# Known limitation: session revocation failing is currently logged but does not
# change the overall result. In a production tool the revoke should be a critical
# step whose failure marks the offboarding "incomplete", since it is the control
# that stops an already-issued token from continuing to work.

param(
    [Parameter(Mandatory)][string]$UserPrincipalName
)

Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Users.Actions
Import-Module Microsoft.Graph.Groups

try {
    $user = Get-MgUser -UserId $UserPrincipalName -ErrorAction Stop
}
catch {
    Write-Host "User not found: $UserPrincipalName" -ForegroundColor Red
    return
}

$actions = @()

# 1. Disable the account
try {
    Update-MgUser -UserId $user.Id -AccountEnabled:$false -ErrorAction Stop
    $actions += "Account disabled"
    Write-Host "Disabled account" -ForegroundColor Green
}
catch { $actions += "Disable FAILED: $($_.Exception.Message)" }

# 2. Revoke all active sessions/refresh tokens (forces re-auth everywhere)
try {
    Revoke-MgUserSignInSession -UserId $user.Id -ErrorAction Stop | Out-Null
    $actions += "Sessions revoked"
    Write-Host "Revoked active sessions" -ForegroundColor Green
}
catch { $actions += "Revoke FAILED: $($_.Exception.Message)" }

# 3. Remove from all groups (capture them first for the audit record)
$groups = Get-MgUserMemberOfAsGroup -UserId $user.Id -All
foreach ($g in $groups) {
    try {
        Remove-MgGroupMemberByRef -GroupId $g.Id -DirectoryObjectId $user.Id -ErrorAction Stop
        $actions += "Removed from $($g.DisplayName)"
        Write-Host "Removed from $($g.DisplayName)" -ForegroundColor Green
    }
    catch { $actions += "Remove from $($g.DisplayName) FAILED: $($_.Exception.Message)" }
}

# 4. Remove assigned licenses (reclaim cost)
try {
    $lic = Get-MgUserLicenseDetail -UserId $user.Id
    if ($lic) {
        $skus = $lic.SkuId
        Set-MgUserLicense -UserId $user.Id -AddLicenses @() -RemoveLicenses $skus -ErrorAction Stop | Out-Null
        $actions += "Licenses removed ($($skus.Count))"
        Write-Host "Removed $($skus.Count) license(s)" -ForegroundColor Green
    } else {
        $actions += "No licenses to remove"
    }
}
catch { $actions += "License removal FAILED: $($_.Exception.Message)" }

# 5. Hide from Global Address List
try {
    Update-MgUser -UserId $user.Id `
        -AdditionalProperties @{ showInAddressList = $false } -ErrorAction Stop
    $actions += "Hidden from GAL"
    Write-Host "Hidden from address list" -ForegroundColor Green
}
catch { $actions += "GAL hide FAILED: $($_.Exception.Message)" }

# 6. Clear the manager attribute
try {
    Remove-MgUserManagerByRef -UserId $user.Id -ErrorAction Stop
    $actions += "Manager cleared"
    Write-Host "Cleared manager" -ForegroundColor Green
}
catch { $actions += "Manager clear skipped/failed: $($_.Exception.Message)" }

# Offboarding record for audit trail
[pscustomobject]@{
    User          = $UserPrincipalName
    OffboardedUtc = (Get-Date).ToUniversalTime().ToString('u')
    GroupsRemoved = ($groups.DisplayName -join '; ')
    Actions       = ($actions -join ' | ')
} | Export-Csv "offboard-$($user.Id)-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv" -NoTypeInformation

Write-Host "`nOffboarding complete for $UserPrincipalName" -ForegroundColor Cyan
