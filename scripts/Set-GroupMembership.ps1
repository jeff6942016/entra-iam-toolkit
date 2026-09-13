# Set-GroupMembership.ps1
# Creates security groups if missing and adds users to them from a CSV.
# Idempotent: safe to run repeatedly. Existing groups are reused and users
# already in a group are skipped rather than erroring.
#
# Usage:   ./Set-GroupMembership.ps1 -CsvPath ./samples/group-assignments.csv
# Scopes:  Group.ReadWrite.All

param(
    [Parameter(Mandatory)][string]$CsvPath
)

Import-Module Microsoft.Graph.Groups

$assignments = Import-Csv -Path $CsvPath
$results     = @()
$groupCache  = @{}   # avoid re-querying the same group per row

foreach ($a in $assignments) {
    try {
        # Resolve the user (UPN or object id both work)
        $user = Get-MgUser -UserId $a.UserPrincipalName -ErrorAction Stop

        # Get the group from cache, or look it up, or create it
        if ($groupCache.ContainsKey($a.GroupName)) {
            $group = $groupCache[$a.GroupName]
        }
        else {
            $group = Get-MgGroup -Filter "displayName eq '$($a.GroupName)'"
            if (-not $group) {
                $nick  = ($a.GroupName -replace '[^a-zA-Z0-9]', '').ToLower()
                $group = New-MgGroup -DisplayName $a.GroupName `
                    -MailEnabled:$false `
                    -MailNickname $nick `
                    -SecurityEnabled:$true `
                    -ErrorAction Stop
                Write-Host "Created group $($a.GroupName)" -ForegroundColor Cyan
            }
            $groupCache[$a.GroupName] = $group
        }

        # Idempotency: skip if already a member
        $already = Get-MgGroupMember -GroupId $group.Id -All |
            Where-Object { $_.Id -eq $user.Id }

        if ($already) {
            $status = "Already a member"
            Write-Host "$($a.UserPrincipalName) already in $($a.GroupName)" -ForegroundColor Yellow
        }
        else {
            New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
            $status = "Added"
            Write-Host "Added $($a.UserPrincipalName) to $($a.GroupName)" -ForegroundColor Green
        }

        $results += [pscustomobject]@{
            User = $a.UserPrincipalName; Group = $a.GroupName; Status = $status
        }
    }
    catch {
        $results += [pscustomobject]@{
            User = $a.UserPrincipalName; Group = $a.GroupName
            Status = "Failed: $($_.Exception.Message)"
        }
        Write-Host "Failed $($a.UserPrincipalName) -> $($a.GroupName): $($_.Exception.Message)" -ForegroundColor Red
    }
}

$results | Export-Csv "group-membership-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv" -NoTypeInformation
$results | Format-Table -AutoSize
