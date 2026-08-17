# Office MFCS Workbench POC

A standalone React POC for buyer drafting, manager approval, and posting Office style/order transactions through the existing Oracle MFCS controller.

It also includes a read-only MFCS State Viewer. Enter an RMS order, style, or SKU number to inspect the connected `ITEM_MASTER`, sourcing, item-location, purchase-order, UDA, and simulator REST journal state.

The application supports all five operations:

- `CREATE_ALL`
- `CREATE_STYLE`
- `CREATE_ORDER`
- `MODIFY_STYLE`
- `MODIFY_ORDER`

This project is outside the `OracleMfcsController` Git repository and has not been pushed to GitHub.

## Architecture

- React, TypeScript, Vite, React Router, React Hook Form, Zod
- Oracle schema `OFFICE_MFCS_UI_APP` for drafts, workflow state, approvals, approved payloads, integration responses, and append-only history
- ORDS workflow API at `/ords/office_mfcs_ui_app/office-workflow/v1`
- Read-only state endpoint at `GET /ords/office_mfcs_ui_app/office-workflow/v1/state/:identifier`
- Existing `OFFICE_MFCS_APP.OFFICE_MFCS_API_PKG` for all MFCS controller processing
- RMS-shaped Local MFCS tables as the sole merchandising state store
- Simulated authentication through the application user selector

There is no browser storage or alternate integration path. Drafts, workflow transitions, approvals, integration payloads, integration responses, and history are stored and processed in Oracle.

## Run

```powershell
pnpm install
pnpm dev
```

The development URL is `http://127.0.0.1:4173`. Vite proxies the workflow API to the local ORDS HTTPS listener. The browser never calls the MFCS controller directly; Oracle PL/SQL owns that integration hop.

These scripts also work with npm where npm is installed:

```powershell
npm install
npm run dev
npm run build
npm test
```

## Database Installation

Run `database/000_create_schema.sql` as `ADMIN`. It creates `OFFICE_MFCS_UI_APP`, grants the minimum POC schema privileges, grants execution on the existing controller package, grants read-only access to the Local MFCS RMS tables, and enables ADMIN proxy access.

Then connect through the new schema and run:

```sql
@database/install.sql
```

The current local Oracle container already has this schema and ORDS module installed.

For an existing workflow installation, `database/install_state_viewer.sql` recompiles only the state package and ORDS module after the ADMIN grants have been applied.

## Configuration

Copy `.env.example` values into the process environment or a local `.env` file when overriding defaults:

```text
VITE_WORKFLOW_API_BASE_URL=/workflow-api
```

Do not put database credentials or OAuth client secrets in Vite variables. Vite variables are bundled into browser code.

## Users

Use the selector in the header:

- Jane Buyer — Buyer
- Michael Manager — Manager

The manager cannot edit request data, and a submitter cannot approve their own request. This is role simulation, not production authentication or authorization.

## Demonstration Flows

Success:

1. Select Jane Buyer and create any operation.
2. Save the draft, review it, and submit it.
3. Switch to Michael Manager and open Approval Queue.
4. Approve and post.
5. Open the request to see generated style, SKU, and order identifiers as applicable.

Return and correction:

1. Submit as Jane and open the request as Michael.
2. Return it with a mandatory reason.
3. Switch to Jane, choose Correct Request, edit, and resubmit.
4. The source version increments and return history is preserved in Oracle.

MFCS state lookup:

1. Open `MFCS state` from the left navigation.
2. Search for an order number, style number, or SKU number.
3. Review the item hierarchy, sourcing, orders, locations, UDAs, and REST history tabs.

The current seeded simulator examples are order `10700008`, style `3000024`, and SKU `3000025`. These values change when the simulator is reset and reseeded.

## Verification

```powershell
pnpm test
pnpm run build
./database/workflow_backend_smoke.ps1
./database/state_viewer_smoke.ps1
```

The workflow smoke covers save, submit, return, correction/versioning, resubmit, live controller posting, and verification that the resulting style and order are readable from Local MFCS. The state viewer smoke verifies order, style, SKU, and not-found lookups through live ORDS handlers.

## Operational Logging

Workflow and state-viewer packages write structured events through
`OFFICE_WORKFLOW_LOG_PKG`. The logger uses an autonomous transaction so failures
remain visible after the workflow transaction rolls back.

```sql
select log_level, package_name, operation_name, request_id, message, created_at
from office_workflow_log
order by log_id desc;
```

PL/SQL parameters use `p_`; local variables and cursor records use `l_`; constants
use `c_`. Logging calls intentionally avoid credentials and full sensitive payloads.

## POC Limitations

- Identity is simulated and ORDS routes are unauthenticated for local development.
- The workflow API must not be exposed to a shared or internet-accessible environment unchanged.
- Notifications, delegation, packs, detailed UDA maintenance, and production accessibility certification remain out of scope.
- Real tenant OpenAPI schemas and business mappings remain authoritative for actual MFCS testing.
