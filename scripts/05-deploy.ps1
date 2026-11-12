. "$PSScriptRoot\env.ps1"
RequireAws
# Re-run this script any time to redeploy: it reuses the instance if it already exists.

Step "Key pair + security group"
if (-not (Test-Path "$Work\nextwork-keypair.pem")) {
    aws ec2 create-key-pair --key-name nextwork-keypair --query KeyMaterial --output text | Set-Content -Encoding ascii "$Work\nextwork-keypair.pem"
}
$sg = aws ec2 describe-security-groups --filters Name=group-name,Values=web-sg --query "SecurityGroups[0].GroupId" --output text
if (-not $sg -or $sg -eq "None") {
    $sg = aws ec2 create-security-group --group-name web-sg --description web --query GroupId --output text
    aws ec2 authorize-security-group-ingress --group-id $sg --protocol tcp --port 8080 --cidr 0.0.0.0/0
}

Step "Launch instance (a Docker container)"
$id = aws ec2 describe-instances --filters Name=tag:Name,Values=nextwork-web Name=instance-state-name,Values=running --query "Reservations[0].Instances[0].InstanceId" --output text
$fresh = $false
if (-not $id -or $id -eq "None") {
    $id = aws ec2 run-instances --image-id ami-amazonlinux2023 --instance-type t2.micro --key-name nextwork-keypair `
        --security-group-ids $sg --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=nextwork-web}]" `
        --query "Instances[0].InstanceId" --output text
    $fresh = $true
}
Write-Host "Instance: $id"
$flociName = docker ps --filter "publish=4566" --format "{{.Names}}" | Select-Object -First 1
Write-Host "Waiting for the instance container (first run pulls the Amazon Linux image, up to 3 min)..."
$c = $null
for ($i = 0; $i -lt 36 -and -not $c; $i++) {
    $c = docker ps --filter "name=$id" --format "{{.Names}}" | Where-Object { $_ -notmatch "fwd" } | Select-Object -First 1   # skip the socat port-forwarder container
    if (-not $c) { Start-Sleep 5 }
}
if (-not $c) {
    docker ps -a --format "table {{.Names}}`t{{.Image}}`t{{.Status}}"
    aws ec2 describe-instances --instance-ids $id --query "Reservations[].Instances[].[InstanceId,State.Name]" --output text
    docker logs $flociName --tail 40
    throw "No container for $id appeared - paste the output above."
}
Write-Host "Container: $c"

docker exec $c test -d /opt/tomcat
if ($LASTEXITCODE -ne 0) {
    Step "Install Java + Tomcat + AWS CLI in the instance"
    docker exec $c sh -c "dnf install -y java-1.8.0-amazon-corretto tar gzip findutils which curl-minimal && (command -v aws >/dev/null || dnf install -y awscli-2)"
    docker exec $c sh -c "curl -fSL https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.89/bin/apache-tomcat-9.0.89.tar.gz | tar xz -C /opt && ln -sfn /opt/apache-tomcat-9.0.89 /opt/tomcat"
    docker exec $c test -x /opt/tomcat/bin/startup.sh
    if ($LASTEXITCODE -ne 0) { throw "Tomcat did not install - see the curl/tar errors above." }
}

Step "Register the instance with SSM (needed so CodeDeploy can run hook scripts)"
$body = Join-Path $Work "ssm.json"
[IO.File]::WriteAllText($body, '{"InstanceId":"' + $id + '"}')
curl.exe -s -X POST http://localhost:4566/ -H "Content-Type: application/x-amz-json-1.1" -H "X-Amz-Target: AmazonSSM.UpdateInstanceInformation" --data-binary "@$body"
aws ssm describe-instance-information --query "InstanceInformationList[].[InstanceId,PingStatus]" --output text

Step "Copy hook scripts into the instance"
docker exec $c rm -rf /scripts
docker cp "$Root\hooks" "${c}:/scripts"

Step "Tag the instance (the deployment group finds instances by this tag)"
aws ec2 create-tags --resources $id --tags Key=Name,Value=nextwork-web
aws ec2 describe-instances --instance-ids $id --query "Reservations[0].Instances[0].Tags" --output json

Step "CodeDeploy app + group (recreated fresh each run)"
aws deploy delete-deployment-group --application-name nextwork-app --deployment-group-name nextwork-dg 2>$null
aws deploy delete-application --application-name nextwork-app 2>$null
aws deploy create-application --application-name nextwork-app --compute-platform Server
aws deploy create-deployment-group --application-name nextwork-app --deployment-group-name nextwork-dg `
    --service-role-arn arn:aws:iam::000000000000:role/codedeploy-role
# Floci bug: CodeDeploy's EC2-tag lookup passes null and silently finds nothing. Workaround: register the
# instance as an on-premises instance (named by its EC2 id) and give the group NO filters = all registered.
aws deploy register-on-premises-instance --instance-name $id --iam-user-arn arn:aws:iam::000000000000:user/devops-iam 2>$null
aws deploy list-on-premises-instances --query instanceNames --output text

# Floci queues CodeDeploy hook commands for an SSM agent and never runs them itself, so this script plays the agent:
# poll ec2messages for queued commands, run them in the instance container, report back with SendReply.
function Invoke-Ssm($op, $body) {
    Invoke-RestMethod -Method Post -Uri "http://localhost:4566/" -ContentType "application/x-amz-json-1.1" `
        -Headers @{ "X-Amz-Target" = "AmazonSSMMessageDeliveryService.$op" } -Body ($body | ConvertTo-Json -Compress)
}
# Drop stale queued commands left by earlier failed deployments (running them would delay the real one past Floci's 500 ms ack window)
do {
    $stale = Invoke-RestMethod -Method Post -Uri "http://localhost:4566/" -ContentType "application/x-amz-json-1.1" `
        -Headers @{ "X-Amz-Target" = "AmazonSSMMessageDeliveryService.GetMessages" } `
        -Body (@{ Destination = $id; MessagesRequestId = [guid]::NewGuid().ToString(); VisibilityTimeoutInSeconds = 30 } | ConvertTo-Json -Compress)
} while (@($stale.Messages).Count -gt 0)
$stopFile = Join-Path $Work "agent.stop"
Remove-Item $stopFile -ErrorAction SilentlyContinue
$agent = Start-Job -FilePath "$Root\ssm-agent.ps1" -ArgumentList $id, $c, $stopFile   # must run BEFORE the deployment is created

Step "Create deployment"
$spec = [IO.File]::ReadAllText("$Root\appspec.yml")   # plain string (Get-Content -Raw adds metadata that breaks ConvertTo-Json)
$rev = Join-Path $Work "revision.json"
[IO.File]::WriteAllText($rev, (@{ revisionType = "AppSpecContent"; appSpecContent = @{ content = $spec } } | ConvertTo-Json -Depth 5))
$dep = aws deploy create-deployment --application-name nextwork-app --deployment-group-name nextwork-dg --revision "file://$rev" --query deploymentId --output text
do {
    Start-Sleep 3
    $st = aws deploy get-deployment --deployment-id $dep --query deploymentInfo.status --output text
    Receive-Job $agent
} until ($st -in "Succeeded","Failed","Stopped")
New-Item -ItemType File $stopFile -Force | Out-Null
Start-Sleep 1
Receive-Job $agent; Remove-Job $agent -Force
Write-Host "Deployment status: $st"
if ($st -ne "Succeeded") {
    Step "Why it failed"
    aws deploy get-deployment --deployment-id $dep --query deploymentInfo.errorInformation
    aws deploy batch-get-deployment-targets --deployment-id $dep --target-ids $id --query "deploymentTargets[0].instanceTarget.lifecycleEvents[].[lifecycleEventName,status,diagnostics.message]" --output text
}

Step "Where is the app? (look for 'Published EC2 instance ... app port 8080 on host port N')"
docker logs $flociName 2>&1 | Select-String "app port"
Write-Host "Open http://localhost:<N>/  (or: docker exec $c curl -s localhost:8080)"
