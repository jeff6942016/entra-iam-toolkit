# Get-AccessReport.ps1
# Exports every user with their group memberships and directory roles to CSV.
# This is the "who has access to what" report an IAM analyst produces constantly.
#
# Usage:   ./Get-AccessReport.ps1
# Scopes:  Directory.Read.All

Import-Module Microsoft.Graph.Users

$users   = Get-MgUser -All -Property Id,DisplayName,UserPrincipalName,AccountEnabled,UserType
$results = @()

foreach ($u in $users) {
    # Strongly-typed lookups return real group/role objects with a DisplayName
    # property. The looser Get-MgUserMemberOf approach depends on an @odata.type
    # key in AdditionalProperties that does not always deserialize, which silently
    # returns empty group columns. See the troubleshooting section in the README.
    $groups = (Get-MgUserMemberOfAsGroup -UserId $u.Id -All).DisplayName
    $roles  = (Get-MgUserMemberOfAsDirectoryRole -UserId $u.Id -All).DisplayName

    $results += [pscustomobject]@{
        DisplayName = $u.DisplayName
        UPN         = $u.UserPrincipalName
        Enabled     = $u.AccountEnabled
        UserType    = $u.UserType
        Groups      = ($groups -join '; ')
        Roles       = ($roles -join '; ')
    }
}

$results | Export-Csv "access-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv" -NoTypeInformation
$results | Format-Table DisplayName, UPN, UserType, Enabled, Groups, Roles -AutoSize
