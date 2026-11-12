param(
    [string]$Name = "DevOps",        # shown on the web page
    [string]$RepoUrl = ""           # e.g. https://github.com/YOURUSER/nextwork-web-project.git (optional, pushes if given)
)
. "$PSScriptRoot\env.ps1"

if (-not (Test-Path "$App\pom.xml")) {
    Step "Generate Maven webapp (in $MavenImage container)"
    if (Test-Path $App) { Remove-Item -Recurse -Force $App }   # clear a half-made folder from a failed run
    docker run --rm -v "${Work}:/work" -w /work $MavenImage mvn -B archetype:generate `
        "-DgroupId=com.nextwork.app" "-DartifactId=nextwork-web-project" `
        "-DarchetypeArtifactId=maven-archetype-webapp" "-DinteractiveMode=false"
    if (-not (Test-Path "$App\pom.xml")) { throw "Maven did not generate the project - see the output above." }
}

Step "Write index.jsp, buildspec.yml, .gitignore"
@"
<html>

<body>

<h2>Hello $Name!</h2>

<p>This is my NextWork web application working!</p>

</body>

</html>
"@ | Set-Content -Encoding ascii "$App\src\main\webapp\index.jsp"

@"
version: 0.2
phases:
  build:
    commands:
      - mvn -B package
artifacts:
  files:
    - nextwork-web-project.war
  base-directory: target
"@ | Set-Content -Encoding ascii "$App\buildspec.yml"

"target/`n" | Set-Content -Encoding ascii "$App\.gitignore"

Step "Test build (expect BUILD SUCCESS and a .war)"
Mvn @("package")
Get-ChildItem "$App\target\*.war"

Step "Git"
Push-Location $App
if (-not (Test-Path .git)) { git init }
git branch -M main
git add .
git commit -m "Updated index.jsp with new content"
if ($RepoUrl) {
    git remote remove origin 2>$null
    git remote add origin $RepoUrl
    Write-Host "Pushing - enter GitHub username and PERSONAL ACCESS TOKEN (repo scope) as the password"
    git push -u origin main
} else {
    Write-Host "Re-run with -RepoUrl <url> to push to GitHub (create an empty public repo first)."
}
Pop-Location
