# Local Deployment

## Prerequisites

- Docker container `adb-free` running the Oracle ADB Free image
- The container has `ADMIN_PASSWORD` and the `myatp_low` wallet alias configured
- Oracle APEX packages `APEX_JSON` and `APEX_WEB_SERVICE` available to both schemas
- PowerShell 7 or Windows PowerShell 5.1
- Node.js and `pnpm` for the React Workbench

The local stack is verified against Oracle APEX `24.2.14`. PL/SQL response
generation uses `APEX_JSON`, while outbound MFCS/OAuth calls use
`APEX_WEB_SERVICE`.

No passwords are stored in the repository. The deployment script reads
`ADMIN_PASSWORD` from the container unless `-AdminPassword` is supplied.

## First Install

From the repository root:

```powershell
.\scripts\deploy-local.ps1 -Mode Install
```

This installs:

- `OFFICE_MFCS_APP`: integration controller and Local MFCS RMS simulator
- `OFFICE_MFCS_UI_APP`: approval workflow and state-viewer backend
- ORDS modules for both schemas
- Required RMS foundation data
- Optional demonstration style `3900000`, SKUs `3900001`/`3900002`, and order `11900000`

`Install` expects the application tables not to exist. It does not drop or reset
an existing installation.

## Upgrade

Deploy package, ORDS, logging, grant, and seed updates without recreating tables:

```powershell
.\scripts\deploy-local.ps1 -Mode Upgrade
```

Useful switches:

```powershell
-SkipFoundationSeed  # Do not merge supplier/location/hierarchy/diff fixtures
-SkipDemoSeed        # Do not merge the stable demonstration style and order
-SkipWorkbench       # Deploy only the controller and Local MFCS simulator
-RunSmokeTests       # Run database/ORDS smoke tests after deployment
```

Foundation and demo seeds use `MERGE`, so they can be applied repeatedly. Skip the
demo seed anywhere that should contain only test-created transactions.

Reapply only the seed data to an existing installation:

```powershell
.\scripts\deploy-local.ps1 -Mode Seed
```

## Verify

```powershell
.\scripts\verify-local.ps1
```

This runs direct Local MFCS REST tests, the live workflow-to-RMS chain, state
lookups, all five operation types, negative permutations, React tests, and a
production frontend build.

## Run The Workbench

```powershell
.\scripts\start-workbench.ps1
```

Open [http://127.0.0.1:4173](http://127.0.0.1:4173). The Vite proxy forwards
workflow calls to `https://127.0.0.1:8443/ords/office_mfcs_ui_app/`.

Useful local endpoints:

- Controller: `https://127.0.0.1:8443/ords/office_mfcs_app/office-mfcs/v1/`
- Local MFCS: `https://127.0.0.1:8443/ords/office_mfcs_app/local-mfcs/`
- Workflow: `https://127.0.0.1:8443/ords/office_mfcs_ui_app/office-workflow/v1/`
