. "$PSScriptRoot\env.ps1"
Step "Remove instance containers and Floci"
$ids = aws ec2 describe-instances --query "Reservations[].Instances[].InstanceId" --output text
if ($ids) { aws ec2 terminate-instances --instance-ids ($ids -split "\s+") }
docker compose -f "$Root\compose.yaml" down
Write-Host "Done. Delete the work\ folder to start from scratch."
