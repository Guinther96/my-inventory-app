param(
  [ValidateSet('Debug', 'Release')]
  [string]$Mode = 'Debug',

  [switch]$UseFlutter
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$localGradleHome = Join-Path $projectRoot '.gradle-user-home'

Write-Host "Project root: $projectRoot"
Write-Host "Using GRADLE_USER_HOME: $localGradleHome"

$env:GRADLE_USER_HOME = $localGradleHome

if (-not (Test-Path $localGradleHome)) {
  New-Item -ItemType Directory -Path $localGradleHome | Out-Null
}

Push-Location $projectRoot
try {
  if ($UseFlutter) {
    if ($Mode -eq 'Release') {
      flutter build apk --release
    } else {
      flutter build apk --debug
    }
  } else {
    Push-Location (Join-Path $projectRoot 'android')
    try {
      if ($Mode -eq 'Release') {
        .\gradlew.bat assembleRelease
      } else {
        .\gradlew.bat assembleDebug
      }
    } finally {
      Pop-Location
    }
  }
} finally {
  Pop-Location
}
