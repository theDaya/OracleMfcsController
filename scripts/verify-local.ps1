[CmdletBinding()]
param(
    [switch] $SkipFrontend
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$appRoot = Join-Path $repoRoot 'apps/office-mfcs-workbench'

# The direct Local MFCS test resets transactional simulator data, so run it
# before the workflow smoke creates the final inspectable style and order.
& (Join-Path $repoRoot 'local-mfcs/tests/local_mfcs_ords_smoke.ps1')
& (Join-Path $appRoot 'database/workflow_backend_smoke.ps1')
& (Join-Path $appRoot 'database/state_viewer_smoke.ps1')
& (Join-Path $repoRoot 'tests/office_mfcs_ords_operation_smoke.ps1')

if (-not $SkipFrontend) {
    Push-Location $appRoot
    try {
        pnpm install --frozen-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Workbench dependency installation failed.' }
        pnpm test
        if ($LASTEXITCODE -ne 0) { throw 'Workbench tests failed.' }
        pnpm run build
        if ($LASTEXITCODE -ne 0) { throw 'Workbench build failed.' }
    } finally {
        Pop-Location
    }
}

Write-Host 'All local verification checks passed.'
