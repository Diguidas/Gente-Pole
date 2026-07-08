$BOT_TOKEN = "8547681704:AAFGgYg9AJjb50zgzOT_D4RxgE2VvviziXo"
$ok = $false

for ($i = 0; $i -lt 15; $i++) {
    try {
        $tunnels = Invoke-RestMethod http://localhost:4040/api/tunnels
        $url = $tunnels.tunnels[0].public_url
        if ($url) {
            Write-Host "Tunel: $url"
            Invoke-RestMethod "https://api.telegram.org/bot$BOT_TOKEN/setWebhook?url=$url" | Out-Null
            Write-Host "Webhook registrado! Pode testar /start no bot do Telegram."
            $ok = $true
            break
        }
    } catch {}
    Start-Sleep -Seconds 2
}

if (-not $ok) {
    Write-Host "Nao consegui pegar a URL do ngrok. Confira a janela polebot-ngrok."
}
