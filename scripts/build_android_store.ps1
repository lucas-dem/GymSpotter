param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$SourceCodeUrl
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$keyProperties = Join-Path $projectRoot 'android\key.properties'

if (-not (Test-Path -LiteralPath $keyProperties)) {
    throw 'android/key.properties is required. A store release must never use the debug signing key.'
}

Push-Location $projectRoot
try {
    $dirty = git status --porcelain
    if ($dirty) {
        throw 'The working tree is not clean. Commit the exact release source before building.'
    }

    $revision = (git rev-parse HEAD).Trim()
    $buildDate = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')

    flutter build appbundle --release `
        --dart-define="SOURCE_CODE_URL=$SourceCodeUrl" `
        --dart-define="SOURCE_REVISION=$revision" `
        --dart-define="BUILD_DATE=$buildDate"
} finally {
    Pop-Location
}
