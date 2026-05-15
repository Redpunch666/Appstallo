@echo off
title Appstallo - Code Signing
echo.
echo ============================================
echo   APPSTALLO - Code Signing
echo ============================================
echo.

:: Zertifikat-Thumbprint (Certum Open Source Developer)
set THUMBPRINT=7E7B00C56C7D0352364399E2B4D1B8CAA32E5796

:: Timestamp-Server (Certum)
set TSAURL=http://time.certum.pl/

:: EXE-Dateien signieren
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$thumb = '%THUMBPRINT%'; " ^
 "$tsa   = '%TSAURL%'; " ^
 "$cert  = Get-ChildItem Cert:\CurrentUser\My\$thumb -ErrorAction SilentlyContinue; " ^
 "if (-not $cert) { Write-Host 'FEHLER: Zertifikat nicht gefunden!' -ForegroundColor Red; exit 1 }; " ^
 "Write-Host \"Zertifikat: $($cert.Subject)\" -ForegroundColor Green; " ^
 "Write-Host \"Gueltig bis: $($cert.NotAfter.ToString('dd.MM.yyyy'))\" -ForegroundColor Green; " ^
 "Write-Host ''; " ^
 "$exes = Get-ChildItem -Path '.\' -Filter '*.exe' -File; " ^
 "if ($exes.Count -eq 0) { Write-Host 'Keine EXE-Dateien im aktuellen Verzeichnis gefunden.' -ForegroundColor Yellow; exit 0 }; " ^
 "foreach ($exe in $exes) { " ^
 "  Write-Host \"Signiere: $($exe.Name)...\" -NoNewline; " ^
 "  $result = Set-AuthenticodeSignature -FilePath $exe.FullName -Certificate $cert -TimestampServer $tsa -HashAlgorithm SHA256; " ^
 "  if ($result.Status -eq 'Valid') { Write-Host ' OK' -ForegroundColor Green } " ^
 "  else { Write-Host \" FEHLER: $($result.StatusMessage)\" -ForegroundColor Red } " ^
 "}"

echo.
echo ============================================
echo   Signierung abgeschlossen
echo ============================================
echo.
pause
