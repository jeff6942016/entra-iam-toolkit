# Export-Logs.ps1
# Exports directory audit logs (all tiers) and sign-in logs (Entra ID P1+ only)
# to timestamped CSVs. The sign-in half degrades gracefully on Free-tier tenants
# instead of failing the whole run.
#
# Usage:   ./Export-Logs.ps1
# Scopes:  AuditLog.Read.All
# Module:  Install-Module Microsoft.Graph.Reports -Scope CurrentUser  (first run)

Import-Module Microsoft.Graph.Reports

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# --- Directory audit logs: works on Free tier ---
try {
    $audit = Get-MgAuditLogDirectoryAudit -All -ErrorAction Stop |
        Select-Object ActivityDateTime,
            ActivityDisplayName,
            @{n='InitiatedBy';e={ $_.InitiatedBy.User.UserPrincipalName }},
            @{n='Target';e={ ($_.TargetResources.UserPrincipalName -join '; ') }},
            Result

    $audit | Export-Csv "audit-log-$stamp.csv" -NoTypeInformation
    Write-Host "Exported $($audit.Count) audit log entries" -ForegroundColor Green
    $audit | Select-Object -First 15 | Format-Table -AutoSize
}
catch {
    Write-Host "Audit log export failed: $($_.Exception.Message)" -ForegroundColor Red
}

# --- Sign-in logs: requires Entra ID P1 or above ---
try {
    $signins = Get-MgAuditLogSignIn -All -ErrorAction Stop |
        Select-Object CreatedDateTime,
            UserPrincipalName,
            AppDisplayName,
            @{n='Status';e={ $_.Status.ErrorCode }},
            @{n='IP';e={ $_.IpAddress }},
            @{n='City';e={ $_.Location.City }}

    $signins | Export-Csv "signin-log-$stamp.csv" -NoTypeInformation
    Write-Host "Exported $($signins.Count) sign-in log entries" -ForegroundColor Green
}
catch {
    Write-Host "Sign-in log export skipped (needs Entra ID P1+): $($_.Exception.Message)" -ForegroundColor Yellow
}
