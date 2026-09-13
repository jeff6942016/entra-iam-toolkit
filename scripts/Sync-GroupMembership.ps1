# Sync-GroupMembership.ps1
# Reconciles a user's actual group memberships against a desired-state CSV.
# Adds missing groups, REMOVES groups not in the desired state (kills privilege
# creep), and leaves correct memberships untouched. This is the Mover control:
# access follows the current role, not the accumulated history.
#
# CSV format: UserPrincipalName,GroupNames  (GroupNames = semicolon-separated)
#   ada@tenant...,Engineering;All-Staff
#
# Usage:   ./Sync-GroupMembership.ps1 -CsvPath ./samples/desired-state.csv
# Scopes:  Group.ReadWrite.All

param(
    [Parameter(Mandatory)][string]$CsvPath
)

Import-Module Microsoft.Graph.Groups

$rows    = Import-Csv -Path $CsvPath
$results = @()

foreach ($r in $rows) {
    try {
        $user = Get-MgUser -UserId $r.UserPrincipalName -ErrorAction Stop

        # Desired groups from the CSV (trimmed, empty entries dropped)
        $desired = @($r.GroupNames -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

        # Current group memberships (names)
        $current = @((Get-MgUserMemberOfAsGroup -UserId $user.Id -All).DisplayName)

        # Compute the deltas
        $toAdd    = $desired | Where-Object { $_ -notin $current }
        $toRemove = $current | Where-Object { $_ -notin $desired }

        foreach ($g in $toAdd) {
            $group = Get-MgGroup -Filter "displayName eq '$g'"
            if (-not $group) {
                $results += [pscustomobject]@{ User=$r.UserPrincipalName; Group=$g; Action="Add SKIPPED: group not found" }
                Write-Host "Group not found: $g" -ForegroundColor Red
                continue
            }
            New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
            $results += [pscustomobject]@{ User=$r.UserPrincipalName; Group=$g; Action="Added" }
            Write-Host "Added $($r.UserPrincipalName) to $g" -ForegroundColor Green
        }

        foreach ($g in $toRemove) {
            $group = Get-MgGroup -Filter "displayName eq '$g'"
            if ($group) {
                Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
                $results += [pscustomobject]@{ User=$r.UserPrincipalName; Group=$g; Action="Removed (creep)" }
                Write-Host "Removed $($r.UserPrincipalName) from $g" -ForegroundColor Yellow
            }
        }

        if (-not $toAdd -and -not $toRemove) {
            $results += [pscustomobject]@{ User=$r.UserPrincipalName; Group="(all)"; Action="Already compliant" }
            Write-Host "$($r.UserPrincipalName) already compliant" -ForegroundColor DarkGray
        }
    }
    catch {
        $results += [pscustomobject]@{ User=$r.UserPrincipalName; Group="-"; Action="Failed: $($_.Exception.Message)" }
        Write-Host "Failed $($r.UserPrincipalName): $($_.Exception.Message)" -ForegroundColor Red
    }
}

$results | Export-Csv "group-sync-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv" -NoTypeInformation
$results | Format-Table -AutoSize