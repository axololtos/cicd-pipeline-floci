param([string]$InstanceId, [string]$Container, [string]$StopFile)
# Stand-in for the SSM agent. Floci queues CodeDeploy hook commands for an agent and fails the hook if the
# command isn't acknowledged within ~500 ms, so this polls every 100 ms. Started as a background job by 05-deploy.ps1.
function Invoke-Ssm($op, $body) {
    Invoke-RestMethod -Method Post -Uri "http://localhost:4566/" -ContentType "application/x-amz-json-1.1" `
        -Headers @{ "X-Amz-Target" = "AmazonSSMMessageDeliveryService.$op" } -Body ($body | ConvertTo-Json -Compress)
}
while (-not (Test-Path $StopFile)) {
    try {
        $r = Invoke-Ssm "GetMessages" @{ Destination = $InstanceId; MessagesRequestId = [guid]::NewGuid().ToString(); VisibilityTimeoutInSeconds = 30 }
        foreach ($m in @($r.Messages)) {
            if (-not $m) { continue }
            Invoke-Ssm "AcknowledgeMessage" @{ MessageId = $m.MessageId } | Out-Null
            $p = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($m.Payload)) | ConvertFrom-Json
            $cmd = ($p.Parameters.commands -join "`n")
            "[agent] running in instance: $cmd"
            $out = (& docker exec $Container sh -c $cmd 2>&1 | Out-String); $rc = $LASTEXITCODE
            if ($out.Trim()) { $out.TrimEnd() }
            $status = if ($rc -eq 0) { "Success" } else { "Failed" }
            $reply = @{ runtimeStatus = @{ "aws:runShellScript" = @{ status = $status; returnCode = $rc; standardOutput = $out; standardError = "" } } } | ConvertTo-Json -Depth 5 -Compress
            Invoke-Ssm "SendReply" @{ MessageId = $m.MessageId; Payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($reply)) } | Out-Null
            "[agent] exit code $rc"
        }
    } catch { "[agent] error: $($_.Exception.Message)" }
    Start-Sleep -Milliseconds 100
}
