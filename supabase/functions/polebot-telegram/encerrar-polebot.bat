@echo off
echo Encerrando polebot (deno + ngrok)...
taskkill /FI "WINDOWTITLE eq polebot-deno*" /T /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq polebot-ngrok*" /T /F >nul 2>&1
taskkill /IM deno.exe /F >nul 2>&1
taskkill /IM ngrok.exe /F >nul 2>&1
echo Feito.
pause
