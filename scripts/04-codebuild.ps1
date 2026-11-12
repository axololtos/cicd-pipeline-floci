. "$PSScriptRoot\env.ps1"
RequireAws

Step "Buckets"
aws s3 mb s3://nextwork-source
aws s3 mb s3://nextwork-artifacts

Step "Zip source (tar.exe makes Linux-safe zips) and upload"
$zip = Join-Path $Work "source.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Push-Location $App
tar.exe -a -c -f $zip pom.xml buildspec.yml src
Pop-Location
aws s3 cp $zip s3://nextwork-source/source.zip

Step "CodeBuild project"
aws codebuild create-project --name nextwork-build `
    --source "type=S3,location=nextwork-source/source.zip" `
    --artifacts "type=S3,location=nextwork-artifacts,packaging=NONE" `
    --environment "type=LINUX_CONTAINER,image=$MavenImage,computeType=BUILD_GENERAL1_SMALL" `
    --service-role arn:aws:iam::000000000000:role/codebuild-role

Step "Start build and wait"
$id = aws codebuild start-build --project-name nextwork-build --query build.id --output text
do {
    Start-Sleep 5
    $s = aws codebuild batch-get-builds --ids $id --query "builds[0].[buildStatus,buildComplete]" --output text
    Write-Host $s
} until ($s -match "True")

Step "Artifacts in S3"
aws s3 ls s3://nextwork-artifacts --recursive
$key = aws s3api list-objects-v2 --bucket nextwork-artifacts --query "Contents[?ends_with(Key,'.war')].Key | [0]" --output text
Write-Host "WAR key: $key"
[IO.File]::WriteAllText("$Root\hooks\war-key.txt", $key.Trim())   # read by the deploy hook
if ($s -notmatch "SUCCEEDED") { Write-Host "BUILD DID NOT SUCCEED - run: aws logs tail /aws/codebuild/nextwork-build" -ForegroundColor Red }
