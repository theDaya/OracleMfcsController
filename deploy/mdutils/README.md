# Connecting to the deployment database

The integration schema is deployed to **mdutilstst01**, not to a local container.
Oracle **23.26.2.0.0**, PDB `FREEPDB1`, schema `MFCS_INTEGRATION`.

This is a normal Oracle server, not Autonomous: plain TCP on a service name, no
wallet, no TCPS. `TNS_ADMIN` is irrelevant here — connect with an EZConnect string.

## Setup

Credentials live in `deploy/mdutils/connect.env`, which is **gitignored and must stay
that way** — this repository has a public remote. Create it once:

```bash
cat > deploy/mdutils/connect.env <<'ENV'
DB_HOST=mdutilstst01.truworths.co.za
DB_PORT=1521
DB_SERVICE=FREEPDB1
DB_USER=MFCS_INTEGRATION
DB_PASSWORD=<the password>
DB_CONN="${DB_USER}/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE}"
SQLCL=/c/oracleTools/sqlcl/bin/sql.exe
ENV
```

## Running SQL

```bash
deploy/mdutils/sql.sh myscript.sql           # run a file
echo "select count(*) from request;" | deploy/mdutils/sql.sh
```

The wrapper strips SQLcl's JVM warnings, which otherwise precede every result.

## The connect string form matters

Use the **service-name** form:

```
MFCS_INTEGRATION/<pw>@//mdutilstst01.truworths.co.za:1521/FREEPDB1
```

The colon form `host:1521:FREEPDB1` is SID syntax and will not connect —
`FREEPDB1` is a PDB service name.

## Checking the token before you debug anything

Bearer tokens last an hour, and a stale one makes every MFCS step fail with
`-20950`. `SECRET.UPDATED_AT` is not trustworthy — the row is sometimes updated by
hand. Decode the token's own `exp` claim instead:

```bash
deploy/mdutils/sql.sh deploy/mdutils/token_status.sql
```
