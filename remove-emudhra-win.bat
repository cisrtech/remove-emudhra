@echo off
rem ============================================================
rem  distrust-emudhra.bat
rem  Finds eMudhra / emSign certificates in the machine and user
rem  root and intermediate stores, exports a backup of each, adds
rem  them to the "Disallowed" (Untrusted Certificates) store and
rem  deletes them from the trusted stores.
rem  Run from an ELEVATED command prompt.
rem ============================================================
setlocal
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [X] This script must be run as Administrator.
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$pat='eMudhra|emSign';" ^
 "$bk=Join-Path $env:SystemDrive ('cert-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss'));" ^
 "New-Item -ItemType Directory -Force $bk | Out-Null;" ^
 "$stores='Cert:\LocalMachine\Root','Cert:\LocalMachine\AuthRoot','Cert:\LocalMachine\CA','Cert:\CurrentUser\Root','Cert:\CurrentUser\CA';" ^
 "$hits = foreach ($s in $stores) { Get-ChildItem $s | Where-Object { $_.Subject -match $pat -or $_.Issuer -match $pat -or $_.FriendlyName -match $pat } };" ^
 "if (-not $hits) { Write-Host '[i] No eMudhra/emSign certificates found in root or intermediate stores.' };" ^
 "foreach ($c in $hits) {" ^
 "  $exp = Join-Path $bk ($c.Thumbprint + '.cer');" ^
 "  Export-Certificate -Cert $c -FilePath $exp | Out-Null;" ^
 "  Write-Host ('[>] Distrusting: ' + $c.Subject);" ^
 "  $dis = New-Object System.Security.Cryptography.X509Certificates.X509Store('Disallowed','LocalMachine');" ^
 "  $dis.Open('ReadWrite'); $dis.Add($c); $dis.Close();" ^
 "  Remove-Item -LiteralPath $c.PSPath -Force;" ^
 "  Write-Host ('    removed from store, backup at ' + $exp)" ^
 "};" ^
 "$left = foreach ($s in $stores) { Get-ChildItem $s | Where-Object { $_.Subject -match $pat -or $_.Issuer -match $pat } };" ^
 "if ($left) { Write-Host '[X] Some certificates could not be removed (see above).' }" ^
 "else { Write-Host '[OK] Stores clean. eMudhra/emSign is now explicitly untrusted on this machine.' };" ^
 "Write-Host ('Backups saved under ' + $bk)"

echo.
echo Restart browsers and services so they pick up the change.
endlocal
