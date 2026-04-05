param(
    [string]$TargetTriple = 'x86_64-pc-windows-msvc',
    [string]$Version,
    [switch]$NoClean
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$cargoTomlPath = Join-Path $repoRoot 'Cargo.toml'
$installerScriptPath = Join-Path $repoRoot 'installer\srun-cup.iss'
$stageDir = Join-Path $repoRoot 'build\win-installer-stage'
$outputDir = Join-Path $repoRoot 'build\release'

if (-not $Version) {
    $Version = (Select-String -Pattern '^version *= *"([^"]+)"$' -Path $cargoTomlPath | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1)
}

if (-not $Version) {
    throw 'Failed to detect version from Cargo.toml. Provide -Version explicitly.'
}

if (-not (Test-Path $installerScriptPath)) {
    throw "Installer script not found: $installerScriptPath"
}

$iscc = (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
    $possible = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    )

    foreach ($p in $possible) {
        if (Test-Path $p) {
            $iscc = $p
            break
        }
    }
}

if (-not $iscc) {
    throw 'ISCC.exe not found. Install Inno Setup 6 first.'
}

Push-Location $repoRoot
try {
    Write-Host "Building srun.exe for $TargetTriple (release, feature=tls)"
    cargo build --release --target $TargetTriple --features tls

    $builtExe = Join-Path $repoRoot "target\$TargetTriple\release\srun.exe"
    if (-not (Test-Path $builtExe)) {
        throw "Build succeeded but binary not found: $builtExe"
    }

    if ((Test-Path $stageDir) -and (-not $NoClean)) {
        Remove-Item $stageDir -Recurse -Force
    }

    New-Item -Path $stageDir -ItemType Directory -Force | Out-Null
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

    Copy-Item $builtExe (Join-Path $stageDir 'srun.exe') -Force
    Copy-Item (Join-Path $repoRoot 'login-cup.ps1') (Join-Path $stageDir 'login-cup.ps1') -Force
    Copy-Item (Join-Path $repoRoot 'login-cup.bat') (Join-Path $stageDir 'login-cup.bat') -Force
    Copy-Item (Join-Path $repoRoot 'login-cup.vbs') (Join-Path $stageDir 'login-cup.vbs') -Force
    Copy-Item (Join-Path $repoRoot 'README.md') (Join-Path $stageDir 'README.md') -Force
    Copy-Item (Join-Path $repoRoot 'README.zh-CN.md') (Join-Path $stageDir 'README.zh-CN.md') -Force

    Write-Host "Creating installer with Inno Setup: $iscc"
    & $iscc "/DMyAppVersion=$Version" "/DSourceDir=$stageDir" "/DOutputDir=$outputDir" $installerScriptPath

    if ($LASTEXITCODE -ne 0) {
        throw "ISCC failed with exit code $LASTEXITCODE"
    }

    Write-Host "Installer created under: $outputDir"
} finally {
    Pop-Location
}
