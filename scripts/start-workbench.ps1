[CmdletBinding()]
param(
    [int] $Port = 4173,
    [switch] $SkipInstall,
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$appRoot = Join-Path $repoRoot 'apps/office-mfcs-workbench'

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    throw 'pnpm is required. Install Node.js and enable pnpm before starting the Workbench.'
}

Push-Location $appRoot
try {
    if (-not $SkipInstall) {
        pnpm install --frozen-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Workbench dependency installation failed.' }
    }
    if (-not $SkipBuild) {
        pnpm run build
        if ($LASTEXITCODE -ne 0) { throw 'Workbench production build failed.' }
    }
    pnpm exec vite --host 127.0.0.1 --port $Port
} finally {
    Pop-Location
}
