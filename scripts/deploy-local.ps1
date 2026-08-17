[CmdletBinding()]
param(
    [ValidateSet('Install', 'Upgrade', 'Seed')]
    [string] $Mode = 'Upgrade',
    [string] $ContainerName = 'adb-free',
    [string] $ServiceAlias = 'myatp_low',
    [string] $WalletDirectory = '/u01/app/oracle/wallets/tls_wallet',
    [string] $AdminPassword,
    [switch] $SkipFoundationSeed,
    [switch] $SkipDemoSeed,
    [switch] $SkipWorkbench,
    [switch] $RunSmokeTests
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$controllerSchema = 'OFFICE_MFCS_APP'
$workbenchSchema = 'OFFICE_MFCS_UI_APP'

function Assert-SafeConnectionValue {
    param([string] $Value, [string] $Name)
    if ($Value -notmatch '^[A-Za-z0-9_./-]+$') {
        throw "$Name contains unsupported characters."
    }
}

function Resolve-AdminPassword {
    if (-not [string]::IsNullOrWhiteSpace($AdminPassword)) {
        return $AdminPassword
    }

    $containerEnvironment = & docker inspect $ContainerName --format '{{range .Config.Env}}{{println .}}{{end}}'
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect Docker container $ContainerName."
    }

    $passwordLine = $containerEnvironment | Where-Object { $_ -like 'ADMIN_PASSWORD=*' } | Select-Object -First 1
    if (-not $passwordLine) {
        throw 'ADMIN_PASSWORD was not supplied and is not available in the container environment.'
    }
    return $passwordLine.Substring('ADMIN_PASSWORD='.Length)
}

function Get-ConnectionName {
    param([string] $SchemaName)
    $escapedPassword = $script:ResolvedAdminPassword.Replace('"', '""')
    if ($SchemaName -eq 'ADMIN') {
        return "admin/`"$escapedPassword`"@$ServiceAlias"
    }
    return "admin[$($SchemaName.ToLowerInvariant())]/`"$escapedPassword`"@$ServiceAlias"
}

function Invoke-SqlText {
    param(
        [string] $SchemaName,
        [string] $SqlText,
        [string] $Label
    )

    Write-Host "[$SchemaName] $Label"
    $connectionName = Get-ConnectionName $SchemaName
    $sqlPlusInput = @"
set echo off
set feedback on
set serveroutput on
set define off
whenever sqlerror exit failure rollback
connect $connectionName
$SqlText
exit
"@

    $bashCommand = "TNS_ADMIN='$WalletDirectory' sqlplus -s /nolog"
    $output = $sqlPlusInput | & docker exec -i $ContainerName bash -lc $bashCommand
    $exitCode = $LASTEXITCODE
    $outputText = $output -join [Environment]::NewLine
    if ($outputText) {
        Write-Host $outputText
    }
    if ($exitCode -ne 0 -or $outputText -match 'Warning: .*compilation errors') {
        throw "Oracle deployment failed while running $Label."
    }
}

function Invoke-SqlFile {
    param([string] $SchemaName, [string] $RelativePath)
    $absolutePath = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        throw "Deployment file not found: $absolutePath"
    }
    Invoke-SqlText $SchemaName ([IO.File]::ReadAllText($absolutePath)) $RelativePath
}

function Invoke-SqlFiles {
    param([string] $SchemaName, [string[]] $RelativePaths)
    foreach ($relativePath in $RelativePaths) {
        Invoke-SqlFile $SchemaName $relativePath
    }
}

function Assert-SchemaValid {
    param([string] $SchemaName, [string] $ObjectPrefix)
    $sql = @"
declare
    l_invalid_count number;
    l_error_count number;
begin
    select count(*) into l_invalid_count
      from user_objects
     where status = 'INVALID'
       and object_name like '$ObjectPrefix%';

    select count(*) into l_error_count
      from user_errors
     where name like '$ObjectPrefix%';

    if l_invalid_count > 0 or l_error_count > 0 then
        raise_application_error(-20000, 'Invalid objects=' || l_invalid_count || ', compile errors=' || l_error_count);
    end if;
end;
/
"@
    Invoke-SqlText $SchemaName $sql "Validate $ObjectPrefix objects"
}

Assert-SafeConnectionValue $ContainerName 'ContainerName'
Assert-SafeConnectionValue $ServiceAlias 'ServiceAlias'
Assert-SafeConnectionValue $WalletDirectory 'WalletDirectory'

& docker inspect $ContainerName *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Docker container $ContainerName is not available."
}

$script:ResolvedAdminPassword = Resolve-AdminPassword

Invoke-SqlFile 'ADMIN' 'database/000_create_schema.sql'

if ($Mode -eq 'Seed') {
    if (-not $SkipFoundationSeed) {
        Invoke-SqlFile $controllerSchema 'local-mfcs/database/003_local_mfcs_seed.sql'
    }
    if (-not $SkipDemoSeed) {
        Invoke-SqlFile $controllerSchema 'local-mfcs/database/040_local_mfcs_demo_seed.sql'
    }
    $script:ResolvedAdminPassword = $null
    Write-Host 'Local MFCS seed deployment completed successfully.'
    return
}

if ($Mode -eq 'Install') {
    Invoke-SqlFiles $controllerSchema @(
        'database/001_office_mfcs_tables.sql',
        'database/002_office_mfcs_constraints.sql'
    )
}

Invoke-SqlFiles $controllerSchema @(
    'database/003_office_mfcs_config.sql',
    'database/004_office_mfcs_logging_upgrade.sql',
    'database/005_office_mfcs_log_package.sql',
    'database/010_office_mfcs_package_specs.sql',
    'tests/office_mfcs_public_contract_pkg.sql'
)

if ($Mode -eq 'Install') {
    Invoke-SqlFiles $controllerSchema @(
        'local-mfcs/database/001_local_mfcs_tables.sql',
        'local-mfcs/database/002_local_mfcs_constraints.sql'
    )
}

if (-not $SkipFoundationSeed) {
    Invoke-SqlFile $controllerSchema 'local-mfcs/database/003_local_mfcs_seed.sql'
}

Invoke-SqlFiles $controllerSchema @(
    'local-mfcs/database/004_local_mfcs_compatibility_views.sql',
    'local-mfcs/database/005_local_mfcs_log_package.sql',
    'local-mfcs/database/010_local_mfcs_package_spec.sql',
    'local-mfcs/database/011_local_mfcs_package_body.sql',
    'database/011_office_mfcs_package_bodies.sql',
    'database/020_office_mfcs_ords.sql',
    'local-mfcs/database/020_local_mfcs_ords.sql',
    'local-mfcs/database/030_local_mfcs_config.sql'
)

if (-not $SkipDemoSeed) {
    Invoke-SqlFile $controllerSchema 'local-mfcs/database/040_local_mfcs_demo_seed.sql'
}

Assert-SchemaValid $controllerSchema 'OFFICE_MFCS'
Assert-SchemaValid $controllerSchema 'LOCAL_MFCS'

if (-not $SkipWorkbench) {
    Invoke-SqlFile 'ADMIN' 'apps/office-mfcs-workbench/database/000_create_schema.sql'

    if ($Mode -eq 'Install') {
        Invoke-SqlFile $workbenchSchema 'apps/office-mfcs-workbench/database/001_workflow_tables.sql'
    }

    Invoke-SqlFiles $workbenchSchema @(
        'apps/office-mfcs-workbench/database/002_workflow_logging_upgrade.sql',
        'apps/office-mfcs-workbench/database/003_workflow_log_package.sql',
        'apps/office-mfcs-workbench/database/004_workflow_http_package.sql',
        'apps/office-mfcs-workbench/database/010_workflow_package_spec.sql',
        'apps/office-mfcs-workbench/database/011_workflow_package_body.sql',
        'apps/office-mfcs-workbench/database/012_state_viewer_package_spec.sql',
        'apps/office-mfcs-workbench/database/013_state_viewer_package_body.sql',
        'apps/office-mfcs-workbench/database/020_workflow_ords.sql'
    )
    Assert-SchemaValid $workbenchSchema 'OFFICE_WORKFLOW'
    Assert-SchemaValid $workbenchSchema 'OFFICE_MFCS_STATE'
}

if ($RunSmokeTests) {
    & (Join-Path $repoRoot 'local-mfcs/tests/local_mfcs_ords_smoke.ps1')
    if (-not $SkipWorkbench) {
        & (Join-Path $repoRoot 'apps/office-mfcs-workbench/database/workflow_backend_smoke.ps1')
        & (Join-Path $repoRoot 'apps/office-mfcs-workbench/database/state_viewer_smoke.ps1')
    }
}

$script:ResolvedAdminPassword = $null
Write-Host 'Local MFCS stack deployment completed successfully.'
