param([Parameter(Mandatory)][string]$GitHubUser)
. "$PSScriptRoot\env.ps1"
RequireAws

Step "Create pipeline: GitHub -> CodeBuild -> CodeDeploy"
$p = @{ pipeline = @{
  name = "nextwork-pipeline"
  roleArn = "arn:aws:iam::000000000000:role/codepipeline-role"
  artifactStore = @{ type = "S3"; location = "nextwork-artifacts" }
  stages = @(
    @{ name = "Source"; actions = @(@{ name = "Source"
        actionTypeId = @{ category = "Source"; owner = "ThirdParty"; provider = "GitHub"; version = "1" }
        configuration = @{ Owner = $GitHubUser; Repo = "nextwork-web-project"; Branch = "main"; OAuthToken = "unused" }
        outputArtifacts = @(@{ name = "SourceOutput" }) }) },
    @{ name = "Build"; actions = @(@{ name = "Build"
        actionTypeId = @{ category = "Build"; owner = "AWS"; provider = "CodeBuild"; version = "1" }
        configuration = @{ ProjectName = "nextwork-build" }
        inputArtifacts = @(@{ name = "SourceOutput" }); outputArtifacts = @(@{ name = "BuildOutput" }) }) },
    @{ name = "Deploy"; actions = @(@{ name = "Deploy"
        actionTypeId = @{ category = "Deploy"; owner = "AWS"; provider = "CodeDeploy"; version = "1" }
        configuration = @{ ApplicationName = "nextwork-app"; DeploymentGroupName = "nextwork-dg" }
        inputArtifacts = @(@{ name = "BuildOutput" }) }) }
  ) } }
$f = Join-Path $Work "pipeline.json"
[IO.File]::WriteAllText($f, ($p | ConvertTo-Json -Depth 10))
aws codepipeline create-pipeline --cli-input-json "file://$f"

Step "Run it"
aws codepipeline start-pipeline-execution --name nextwork-pipeline
do { Start-Sleep 8
     $state = aws codepipeline get-pipeline-state --name nextwork-pipeline --query "stageStates[].[stageName,latestExecution.status]" --output text
     $line = $state -join " | "; Write-Host $line; Write-Host "--" } until ($line -notmatch "InProgress|None")

Write-Host @"

KNOWN GAPS to check:
 1) CodeBuild still reads s3://nextwork-source/source.zip, not the GitHub artifact. After editing code, re-run 04-codebuild.ps1 (re-zips) or rebuild the zip.
 2) The Deploy stage may say Succeeded without running hooks (pipeline sends an S3 revision, not appspec content).
    Test: change Hello text, re-run 04, start the pipeline, reload the page. If unchanged, redeploy with 05-deploy.ps1.
"@
