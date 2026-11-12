. "$PSScriptRoot\env.ps1"
RequireAws

Step "IAM roles (Floci needs the ARNs; it does not enforce them by default)"
foreach ($r in @(@("codebuild-role","codebuild"), @("codedeploy-role","codedeploy"), @("codepipeline-role","codepipeline"))) {
    $trust = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"' + $r[1] + '.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    $f = Join-Path $Work "trust-$($r[1]).json"
    [IO.File]::WriteAllText($f, $trust)
    aws iam create-role --role-name $r[0] --assume-role-policy-document "file://$f" --query Role.Arn --output text
}

Step "CodeArtifact domain + repo"
aws codeartifact create-domain --domain nextwork
aws codeartifact create-repository --domain nextwork --repository nextwork-devops-cicd
aws codeartifact get-repository-endpoint --domain nextwork --repository nextwork-devops-cicd --format maven

Step "Token + settings.xml"
$token = aws codeartifact get-authorization-token --domain nextwork --query authorizationToken --output text
$settings = Join-Path $Work "settings.xml"
@"
<settings><servers><server>
  <id>codeartifact</id><username>aws</username><password>`${env.CODEARTIFACT_AUTH_TOKEN}</password>
</server></servers></settings>
"@ | Set-Content -Encoding ascii $settings

Step "mvn deploy to CodeArtifact (container -> host.docker.internal)"
$url = "http://host.docker.internal:4566/codeartifact/maven/nextwork/nextwork-devops-cicd/"
Mvn @("deploy","-DskipTests","-DaltDeploymentRepository=codeartifact::default::$url") -Extra @(
    "-v","${settings}:/root/.m2/settings.xml","-e","CODEARTIFACT_AUTH_TOKEN=$token")
Write-Host "`nExpect BUILD SUCCESS above. (Artifacts are lost if Floci restarts.)"
