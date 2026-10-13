# The controller in RDS

The MFCS controller, renamed to the Oracle Database Naming Standard and installed into the RDS
schema `MFCS_RDS_CUSTOM`, workspace `MFCS`, talking to MFCS **STG** - the tenant `MFCS_RDS`
replicates, so what validation reads and what the controller writes are the same tenant.

The `database/` tree beside this one is the original, still installed on mdutils because the two
APEX consoles run against it. New work goes here. The original takes fixes only.

## What is here, and what is not

| Here | Not here |
| --- | --- |
| 8 controller tables, 15 packages, ORDS handler scripts | The consoles: `UI_DRAFT*`, `POC_*`, `ui_pkg`, `poc_style_pkg`, apps 102 and 103 |
| Four views over the RDS hierarchy | `SECRET` and the `STATIC_BEARER` token path |
| | The SYS-run ACL and credential scripts - in RDS those are not ours to run |

**Names.** Application `IE` (Induction Engine), functional area `MFCS`. Both are new codes and
need the database owner's agreement under the standard. The full old-to-new mapping is in
`docs/database-objects.md`.

**Four changes beyond the rename**, and only these:

1. **One auth mode.** `IE_MFCS_CLIENT` keeps only the APEX credential store. The hand-pasted
   bearer token, its `SECRET` table and the unused wallet settings are gone.
2. **The hierarchy comes from RDS.** `IE_MFCS_MASTER_DATA` loads groups, departments, classes and
   subclasses from `MFCS_RDS.RDS_WV_*` through `IE_MFCS_VW_*`, which also drop rows RDS keeps
   after a delete. Everything else in master data still comes from the REST feeds, for now.
3. **Configuration** defaults to the `MFCS` workspace and OAuth.
4. **The correlation lookup authenticates.** In the original it sent an empty bearer under OAuth,
   was always answered 401, and recovery read that as "no record" and re-ran the step - the
   duplicate write recovery exists to prevent. Proven live on mdutils 2026-10-13: the original
   answers 401, this one 200. A lookup that fails now reports UNKNOWN, which goes to manual review.

Also fixed in passing: the package numbering is now true load order. In the original, the
orchestrator (09) calls the SKU package (14), so a fresh install leaves the orchestrator invalid
until something recompiles it.

## Installing

Everything runs in APEX: **SQL Workshop > SQL Scripts > Upload**, then **Run**. The files are in
`rds/deploy/`. After each, open the run's results and check every statement - SQL Scripts carries
on past an error and reports it at the end.

| # | File | Does | Expect |
| --- | --- | --- | --- |
| 0 | `00_preflight.sql` | Checks only, changes nothing | See its comments. **Send the results back before going on** |
| 1 | *(by hand, below)* | The web credential | |
| 2 | `01_install_tables.sql` | 8 tables, the config seed, 4 views | No errors |
| 3 | `02_install_packages_1.sql` | Packages 01-07 | No errors |
| 4 | `03_install_packages_2.sql` | Packages 08-15 | No errors |
| 5 | `04_verify.sql` | Compile and config check | No invalid objects, `"present":true` |
| 6 | `05_refresh_master_data.sql` | Starts the master data load as a job | Returns at once, job RUNNING |
| 7 | `06_refresh_status.sql` | After ~5 minutes | SUCCEEDED, HTTP 200 throughout, ~417 hierarchy rows |
| 8 | `07_preview_check.sql` | Builds a full call plan, sends nothing | HTTP 200, 14 calls |

Steps 6 and 7 are the first calls from RDS to MFCS, so they are also the test of the credential
and the network ACLs. `06_refresh_status.sql` says what each failure means.

### The web credential

In the `MFCS` workspace: **App Builder > Workspace Utilities > Web Credentials > Create**.

| Field | Value |
| --- | --- |
| Name | `MFCS OAuth2 (client credentials)` |
| Static ID | `MFCS_OAUTH` - must be exactly this |
| Authentication Type | OAuth2 Client Credentials Flow |
| Client ID, Client Secret | The MFCS STG client's. **Typed here and nowhere else** |
| Scope | `rgbu:merch:MFCS-STG3` |
| Valid for URLs | Leave empty |

Neither the id nor the secret can be read back once saved, and credentials are excluded from
application exports. **Never put either in a file in this repository - it has a public remote.**

The token URL is not entered here; `IE_MFCS_CLIENT` passes it on every call from
`MFCS_TOKEN_URL` in `IE_MFCS_CFG_SETTING`.

## ORDS

Not part of the install. `rds/database/30_ords/` holds the handler scripts, renamed to the new
packages and otherwise unchanged, for you to apply as you see fit. One thing to settle when you
do: in the original only `transactions/*/resume` sits behind a privilege. Submitting a
transaction - which creates real MFCS records - needs no authentication at all.

## How this was verified, before going near RDS

The whole layer was installed on mdutils beside the original, in the same schema - every name is
new, so nothing collides - with `rds/tests/stand_in_rds_views.sql` standing in for the RDS views.

- **Compiles in one pass in load order**: 59 objects, zero errors, and no package references an
  object of the original.
- **Preview is byte-identical** to the original's for 28 real stored documents - creates, a
  modify, style-only and style-and-order, and validation rejections - given the same master data.
- **The offline mapper tests** pass 9 of 9, as the original's do.
- **Live, read-only**: the credential resolves, a foundation read answers 200, and a full master
  data refresh runs clean with the hierarchy loaded through the views (21 departments).

Not verified: anything that writes to MFCS. The coverage suite cannot pass on either side until
its fixtures move to STG's restructured colour and size model - step 1 of the agreed plan.

`rds/tests/remove_from_mdutils.sql` takes the side-by-side install off mdutils again.
