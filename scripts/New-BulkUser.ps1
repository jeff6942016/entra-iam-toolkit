# New-BulkUser.ps1
# Bulk-creates Entra ID users from a CSV and writes a provisioning report.
#
# Usage:   ./New-BulkUser.ps1 -CsvPath ./samples/users.csv
# Scopes:  User.ReadWrite.All
#
# Note: temp passwords are exported to CSV here purely as a lab convenience.
# In production you would force self-service password reset or deliver the
# credential over a secure channel, never in a cleartext file.

param(
    [Parameter(Mandatory)][string]$CsvPath
)

Import-Module Microsoft.Graph.Users

$users   = Import-Csv -Path $CsvPath
$results = @()

foreach ($u in $users) {
    # Random 16-char temp password
    $password = -join ((48..57)+(65..90)+(97..122)+33,35,37,64 |
        Get-Random -Count 16 | ForEach-Object {[char]$_})

    $passwordProfile = @{
        Password                      = $password
        ForceChangePasswordNextSignIn = $true
    }

    try {
        # -ErrorAction Stop is critical: without it, a failed create is a
        # non-terminating error that skips the catch block and falls through
        # to the success path with a null $newUser, producing a false "Created".
        $newUser = New-MgUser -DisplayName $u.DisplayName `
            -UserPrincipalName $u.UserPrincipalName `
            -MailNickname $u.MailNickname `
            -AccountEnabled `
            -PasswordProfile $passwordProfile `
            -Department $u.Department `
            -JobTitle $u.JobTitle `
            -UsageLocation $u.UsageLocation `
            -ErrorAction Stop

        $results += [pscustomobject]@{
            UPN          = $newUser.UserPrincipalName
            Id           = $newUser.Id
            TempPassword = $password
            Status       = "Created"
        }
        Write-Host "Created $($u.UserPrincipalName)" -ForegroundColor Green
    }
    catch {
        $results += [pscustomobject]@{
            UPN          = $u.UserPrincipalName
            Id           = $null
            TempPassword = $null
            Status       = "Failed: $($_.Exception.Message)"
        }
        Write-Host "Failed $($u.UserPrincipalName): $($_.Exception.Message)" -ForegroundColor Red
    }
}

$results | Export-Csv "provisioning-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv" -NoTypeInformation
$results | Format-Table -AutoSize
