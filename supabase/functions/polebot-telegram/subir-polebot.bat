@echo off
set DIR=%~dp0

echo Subindo a function (Deno)...
start "polebot-deno" /min powershell -NoExit -Command "$env:Path += ';%USERPROFILE%\.deno\bin'; Set-Location '%DIR%'; deno run --allow-net --allow-env --env-file=.env.local index.ts"

echo Subindo o tunel (ngrok)...
start "polebot-ngrok" /min powershell -NoExit -Command "& '%LOCALAPPDATA%\ngrok\ngrok.exe' http 8000"

echo Aguardando o ngrok ficar pronto...
timeout /t 4 /nobreak >nul

powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%registrar-webhook.ps1"

echo.
echo Pronto. As janelas "polebot-deno" e "polebot-ngrok" continuam abertas minimizadas na barra de tarefas.
echo Para ENCERRAR: rode o encerrar-polebot.bat
pause
