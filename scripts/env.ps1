# Dot-sourced by every script: . "$PSScriptRoot\env.ps1"
$env:AWS_ENDPOINT_URL      = "http://localhost:4566"
$env:AWS_DEFAULT_REGION    = "us-east-1"
$env:AWS_ACCESS_KEY_ID     = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_PAGER             = ""     # stop the CLI pausing at "-- More --"

$Root = $PSScriptRoot
$Work = Join-Path $Root "work"                       # generated files live here
$App  = Join-Path $Work "nextwork-web-project"       # the Maven web app
$MavenImage = "maven:3.5.2-jdk-8"
New-Item -ItemType Directory -Force $Work | Out-Null

function RequireAws {
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        throw "AWS CLI not found. Run: winget install -e --id Amazon.AWSCLI  then open a NEW PowerShell window."
    }
}
function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Mvn([string[]]$MvnArgs, [string]$Dir = $App, [string[]]$Extra = @()) {
    docker run --rm -v "${Dir}:/work" -w /work @Extra $MavenImage mvn -B @MvnArgs
}
