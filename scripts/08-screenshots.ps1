# Shows ONE feature per screen. Take your screenshot (Win+Shift+S), then press Enter for the next.
. "$PSScriptRoot\env.ps1"
RequireAws
$bid = aws codebuild list-builds --query "ids[0]" --output text
$feat = @(
  @("1 Floci account",   { aws sts get-caller-identity --output table }),
  @("2 IAM roles",       { aws iam list-roles --query "Roles[].RoleName" --output table }),
  @("3 S3 buckets",      { aws s3 ls; "--- artifacts:"; aws s3 ls s3://nextwork-artifacts }),
  @("4 CodeArtifact",    { aws codeartifact list-repositories-in-domain --domain nextwork --output table }),
  @("5 CodeBuild",       { aws codebuild batch-get-builds --ids $bid --query "builds[0].[id,buildStatus,currentPhase]" --output table }),
  @("6 EC2 instance",    { aws ec2 describe-instances --query "Reservations[].Instances[].[InstanceId,State.Name,Tags[0].Value]" --output table }),
  @("7 CodeDeploy",      { aws deploy list-deployment-groups --application-name nextwork-app --output table }),
  @("8 CodePipeline",    { aws codepipeline get-pipeline-state --name nextwork-pipeline --query "stageStates[].[stageName,latestExecution.status]" --output table })
)
foreach ($f in $feat) {
    Clear-Host
    Write-Host "FEATURE $($f[0])`n" -ForegroundColor Cyan
    & $f[1]
    Read-Host "`n>> Take the screenshot now, then press Enter for the next feature"
}
