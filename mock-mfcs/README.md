# Oracle MFCS Public-Contract Mock

This stateful HTTP simulator mimics the documented parts of the Oracle Retail Merchandising `MerchIntegrations` chain used by this project. It uses only Node.js built-in modules.

## Run

```powershell
node .\mock-mfcs\server.js
```

The default address is `http://localhost:18080`. Set `PORT` to override it.

Run the tests with:

```powershell
node --test .\mock-mfcs\server.test.js
```

For HTTPS, generate short-lived local fixtures and supply both TLS paths:

```powershell
python .\tests\generate_local_tls.py .\.local-tls --ip-san 192.168.65.254
$env:PORT = '18443'
$env:TLS_KEY_PATH = '..\.local-tls\key.pem'
$env:TLS_CERT_PATH = '..\.local-tls\cert.pem'
node .\mock-mfcs\server.js
```

The generated directory is ignored by Git. Resolve `host.docker.internal` from the Oracle container and use that address for `--ip-san` if it differs.

## Implemented Contracts

| Endpoint | Confidence | Behavior |
| --- | --- | --- |
| `POST /oauth2/v1/token` | Simulator-only | OAuth client-credentials token for local HTTP testing |
| `POST /item/itemNumbers/reserve` | Documented | Generates `items[].item`, type and expiry date |
| `POST /items/create` | Documented subset | Validates collection envelope, reserved IDs and direct `RMS` loading |
| `PUT /items/update` | Documented subset | Updates item data and approval fields |
| Item supplier create/update | Documented subset | Validates items exist and the Oracle collection envelope |
| Item UDA create/update | Provisional without tenant UDA configuration | Accepts documented item/UDA envelope; empty UDA arrays are treated as no-op |
| Item location create/update | Documented subset | Validates item existence and collection envelope |
| Pre-issued PO number create | Documented | Generates nested `orderNumbers` response |
| Purchase order create/update | Documented subset | Requires order number, details and `dataLoadingDestination: RMS` |
| Procurement order GET | Documented subset | Returns persisted order state |
| ReST service status GET | Documented | Returns service metrics by `X-Correlation-ID` |

Exact tenant schema, localization extensions, configured UDAs, differentiators, CFAS, item approval rules, initial pricing behavior, batch dependencies and business foundation data still require the Office tenant OpenAPI and configuration exports.

## Oracle Database E2E

Install `tests/office_mfcs_public_contract_pkg.sql`, deploy the generated CA as an ADB customer-managed wallet, expose it through the `MFCS_MOCK_WALLET_DIR` database directory, grant its `READ` and wallet ACEs to the APEX platform and application schemas, and allow private HTTPS access to `host.docker.internal:18443`. Oracle requires `DIR:MFCS_MOCK_WALLET_DIR` for APEX on ADB; see [Use Web Services with Oracle APEX](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/apex-web-services.html).

Then run:

```sql
@tests/office_mfcs_public_contract_e2e.sql
```

Some local ADB Free images do not fully emulate cloud customer-managed wallet deployment and can return `ORA-29024` for locally signed certificates. In that case, use a publicly trusted HTTPS endpoint for the simulator; the Node contract tests and PL/SQL permutation suites remain deterministic.

## Contract Sources

- [Items REST services](https://docs.oracle.com/en/industries/retail/retail-merchandising-foundation-cloud/latest/rmsob/items-rest.htm)
- [Purchase order REST services](https://docs.oracle.com/en/industries/retail/retail-merchandising-foundation-cloud/latest/rmsob/purch-ord-rest.htm)
- [REST service operation status](https://docs.oracle.com/en/industries/retail/retail-merchandising-foundation-cloud/latest/rmsob/rest-admin.htm)

## Diagnostics

- `GET /health`
- `GET /__admin/state`
- `POST /__admin/reset`
