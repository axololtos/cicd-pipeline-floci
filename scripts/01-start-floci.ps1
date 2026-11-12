. "$PSScriptRoot\env.ps1"
RequireAws
Step "Start Floci (skipped if something already serves port 4566)"
$existing = docker ps --filter "publish=4566" --format "{{.Names}}"
if ($existing) {
    Write-Host "Already running: $existing - reusing it."
} else {
    docker compose -f "$Root\compose.yaml" up -d
    Start-Sleep 5
}
Step "Check CLI -> Floci (expect account 000000000000)"
aws sts get-caller-identity
Write-Host "`nConsole: http://localhost:4566/_floci/ui"
