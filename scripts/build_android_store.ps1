param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$BuildName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[1-9][0-9]{0,8}$')]
    [string]$BuildNumber,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$SourceCodeUrl,

    # Print the exact flutter command without building.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$keyProperties = Join-Path $projectRoot 'android\key.properties'

if (-not $DryRun -and -not (Test-Path -LiteralPath $keyProperties)) {
    throw 'android/key.properties is required. A store release must never use the debug signing key.'
}

Push-Location $projectRoot
try {
    $dirty = git status --porcelain
    if ($dirty -and -not $DryRun) {
        throw 'The working tree is not clean. Commit the exact release source before building.'
    }

    $revision = (git rev-parse HEAD).Trim()
    $buildDate = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')

    # The same arguments as the Codemagic store build. APP_BUILD_NAME/APP_BUILD_NUMBER must match
    # --build-name/--build-number: without them the app shows the pubspec version.
    $arguments = @(
        'build', 'appbundle', '--release',
        "--build-name=$BuildName",
        "--build-number=$BuildNumber",
        "--dart-define=APP_BUILD_NAME=$BuildName",
        "--dart-define=APP_BUILD_NUMBER=$BuildNumber",
        "--dart-define=SOURCE_CODE_URL=$SourceCodeUrl",
        "--dart-define=SOURCE_REVISION=$revision",
        "--dart-define=BUILD_DATE=$buildDate"
    )

    if ($DryRun) {
        if ($dirty) { Write-Output 'Dry run: the working tree is not clean; a real build would stop here.' }
        Write-Output "flutter $($arguments -join ' ')"
        return
    }

    flutter @arguments
} finally {
    Pop-Location
}
