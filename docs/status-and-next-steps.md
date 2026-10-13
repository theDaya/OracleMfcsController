# Status and next steps

Written so work can stop and resume without losing the thread. Current as of **2026-10-13**.

## Session of 2026-10-13 — the controller moves to RDS

**The controller now exists twice.** `rds/` is the same layer renamed to the Oracle Database
Naming Standard - `IE_MFCS_*`, application `IE` (Induction Engine), functional area `MFCS` - for
the RDS schema `MFCS_RDS_CUSTOM`, workspace `MFCS`, tenant STG. The original stays on mdutils for
the two APEX consoles and takes fixes only. ORDS in RDS is being set up by hand, separately.
`rds/README.md` has the mapping, the differences and the install; `docs/database-objects.md` has
the name table.

**Not yet installed in RDS.** Everything is built and proven on mdutils, where the RDS layer was
installed beside the original with stand-ins for the RDS views:

- 59 objects compile in one pass in load order, and none references an object of the original
- preview is **byte-identical** to the original's for 28 real stored documents, given the same
  master data
- the offline mapper tests pass 9 of 9 on both
- the credential resolves, a foundation read answers 200, and a full master data refresh runs
  clean, with the hierarchy loaded through the views: 21 departments, 83 classes, 306 subclasses

Next is `rds/deploy/00_preflight.sql` in RDS, run by hand in APEX SQL Scripts, whose results
decide whether the install goes ahead as written - in particular whether `MFCS_RDS_CUSTOM`
holds SELECT on the `MFCS_RDS` views directly, which a view needs, or only through a role.

**Two defects found along the way, both still live in the original:**

- **Recovery re-ran writes it should have been resolving.** `client_pkg.correlation_status`
  set `Authorization: Bearer ` from the static token and passed no credential, so under OAuth it
  sent an empty bearer and was answered 401 - proven live today. `recovery_pkg` reads a body with
  no `count` as `NO_RECORD` and puts the step back to `PENDING`, so a step whose outcome was
  unknown was simply run again: the duplicate write the whole recovery path exists to prevent.
  Fixed in `rds/` - the lookup authenticates, and a lookup that fails reports UNKNOWN, which goes
  to manual review. **The original still has it.**
- **A fresh install of the original leaves the orchestrator invalid.** `orchestrator_pkg` (09)
  calls `sku_pkg` (14). It works on mdutils only because Oracle recompiles on first use. `rds/`
  is renumbered into true load order.

**Not verified: anything that writes to MFCS from the new layer.** The coverage suite cannot pass
on either side until its fixtures move to the restructured colour and size model.

### STG findings, 2026-10-01 to 2026-10-13

All verified live on STG, and recorded here for the first time:

- **No country of manufacture, no approval** - confirmed again.
- **An unapproved item cannot be ordered.**
- **Country of manufacture can be changed on an approved, ordered item.**
- **An approved item cannot go back to worksheet.**
- **`items/update` ignores `DIFF_1`/`DIFF_2` even in worksheet**, not only once approved.
- **`items/delete` marks an item `D` without checking for orders.** The nightly purge then removed
  an unordered style (`100300035`) and kept an ordered one (`CMF10011048`) in `D`.
- **A purged item number can be reused**: `100300035` was recreated as `MANL` with a different
  colour.

So a style created in the wrong colour can be corrected only by delete, wait for the purge, and
recreate - and only if it has never been ordered. A supported correction route is a question for
the consultant.

### The agreed plan, in order

Agreed 2026-09-28 after the RMS16 comparison, nothing built yet:

1. **Item structure per the consultant**: L1 is a style/colour - a `C` colour in `DIFF_1`, a size
   group in `DIFF_2` - and SKUs carry an `S` size. Never diff type `SC`. A new `SIZE_GROUP` on the
   document, colour and sizes validated against the diff feeds and group membership, a colour
   change refused on modify, `ENSURE_STYLE_SKUS` adding sizes only, and new test fixtures.
2. **A cost-change step**: `cost/costChange/immediate/create` at L1, in the supplier's currency.
3. **`MANL` creates check RDS** (`ITEM_MASTER`) that no style or SKU number is taken, before any write.
4. **Order CFAs** (10 on orders, none on items), and quantity 0 as cancel.
5. **RMS16's guards**: no hierarchy or supplier change on modify, never below received on a PO
   line, delete omitted UDAs and seasons.
6. **Cancel and reinstate order.** Packs are paused.

Also agreed 2026-10-01: remove the post-transaction read-back loops (`ENSURE_STYLE_SKUS` verify,
`SYNC_ORDER_LINES` verify) and move pre-reads to RDS; add an optional `MANUFACTURE_COUNTRY`.
Proposed, not agreed: strip the `S` prefix from size codes in SKU numbers, and fix the supplier
colour code at three characters.

All of it now gets built in `rds/`. Items 3 and the pre-reads are where being next to RDS pays
off, and they need `ITEM_MASTER`, `ITEM_SUPPLIER`, `ORDHEAD` and `ORDLOC` views that are not in
the list of RDS views provided so far. So do `DIFF_IDS` (a diff's type and description, which
`DIFF_GROUP_DETAIL` does not carry), currency and brand, before master data can leave REST.

## Session of 2026-09-28 — the RMS16 comparison, a restructured tenant, and two silent failures

**The RMS16 PLM controller was compared against this layer, and two of its rules were proven live here.**

- `item/suppliers/update` **ignores unit cost on an approved item.** It answers SUCCESS, and the style
  and SKUs read back unchanged (style `100300035`, 48.49 kept against 55 sent). Every cost change on
  an existing style has been lost. `cost/costChange/immediate/create` at L1 level cascades to every SKU
  (all three read back 55), but only in the **supplier's** currency: ZAR was refused and GBP accepted
  for supplier 700087. RMS16 did the same. Not yet built.
- **Zone-price level `CH` does not set retail.** Sent on a real create, it left `unitRetail: 0` while
  `originalRetail: 299` was stored. Reverted. Retail is still the largest gap, and the question is now
  with the consultant.

**STG's diff model was restructured by the consultant.** L1 is a **style/colour**:

- a company colour (type `C`, 100 of them) goes in `DIFF_1`, and a size **group** in `DIFF_2`
- SKUs carry a size (type `S`, 237, now `S`-prefixed: `070` is `S070`)
- `LL`/`HL` group the colours through `industryCode`
- `SC` (48,624 supplier colours, and the only colour group, `RMS_ALL_C`) is marked for deletion and
  must not be used

Proven live: a SKU in another colour is refused under an L1, and `items/update` answers SUCCESS while
leaving `DIFF_1` unchanged. **A colour change is therefore a new L1, not new SKUs.** Our config still
sends `RMS_ALL_C`/`ALL` on every parent, and every test fixture uses `08610` and the old sizes, so
**the live coverage suite cannot pass until step 1 of the plan lands.**

**The master data refresh was quietly incomplete, and is fixed.**

- `fetch_all` now follows every feed's pages. `diffid` had stopped at exactly 500.
- UDAs no longer abort on the first free-form row (`udaListOfValues: null`).
- Banners and channels parse their bare-array responses.
- Diffs load as `DIFF_<type>`, and diff groups as `DIFF_GROUP` / `DIFF_GROUP_MEMBER`, with members
  replaced per group.

STG now yields 27 UDAs with 14,443 values, including the four it lacked, and 12 diff groups.
`merchhier/*` is still empty. **Stale derived rows remain:** 215 colours and 32 sizes that validation
still accepts.

**Order CFAs:** no item or order on STG carries one. The front-end export defines 10 on orders and
none on items.

Test records left on STG: `100300001` (a worksheet L1 with no SKUs), `100300035` (approved),
`CLC09280946` and `CLG09280946`.

## Session of 2026-09-21 — credentials, and the end of the hourly token

**The bearer token is no longer pasted in.** `MFCS_AUTH_MODE = OAUTH_CLIENT_CREDENTIALS` now means
the client id and secret live in the **APEX credential store**, and `apex_web_service` fetches and
refreshes the token itself. Proven live: a `foundation/item` read returned HTTP 200, and
`tests/resume_coverage_tests.sql` passed 20/20 against the tenant with nothing pasted anywhere.

What this replaced, and why each part mattered:

- **A secret in a plain CLOB.** `SECRET.SECRET_VALUE` is readable by anything with SELECT and lands
  in exports and backups. The credential store has no column that returns either the id or the
  secret, and credentials are excluded from application exports.
- **A token cached in a package global.** `client_pkg` held `g_access_token` while its own header
  comment said it did not, and CLAUDE.md forbids it for a real reason: ORDS pools sessions, so the
  cache outlives its request and survives a change of tenant — which surfaces as the documented 403,
  never as anything naming a token. The cache now belongs to `apex_web_service`, in the database.
- **A hand-rolled `client_credentials` POST**, now deleted along with `MFCS_CLIENT_ID` and
  `MFCS_CLIENT_SECRET_REF`.

**The trap worth remembering.** `apex_web_service` is a definer-rights package owned by the APEX
engine schema, so its outbound calls carry **that schema's** network privileges, not the calling
schema's. The IDCS token host needs an ACE for `MFCS_INTEGRATION` *and* one for `APEX_260100`.
Granting only the first passes a `utl_http` test and still fails every real call — which is exactly
what happened here, and why `deploy/mdutils/verify_token_host.sql` now tests both paths and says
which is which. The MFCS host had carried both ACEs all along, which is why this never surfaced until
the database had to reach a second host.

`STATIC_BEARER` still works and is kept as a fallback for an environment without OAuth. The expired
token in `SECRET` is now dead weight rather than the thing everything depends on.

Scripts: `deploy/mdutils/oauth_credential.sql` (creates the credential, contains no secrets and must
never contain any), `grant_token_host_acl.sql` (both ACEs, APEX owner derived not hardcoded),
`verify_token_host.sql`, `show_network_acls.sql`.

## Session of 2026-09-10 — caller-supplied item numbers

Driven by an Office POC that wants MFCS style numbers composed from a Style/Model number and a
Supplier Colour number, rather than taken from `itemNumbers/reserve`.

**`itemNumberType: MANL` lets a caller choose the item number, and nothing needs reserving.** Proven
live on STG: an arbitrary alphanumeric style created and read back, a SKU created under it, 25-character
and punctuated numbers accepted. `ITEM` is unusable for a chosen number - it wants nine characters and a
valid Oracle check digit. Reserving a chosen number through `itemNumbers/manage` changes nothing either
way. The full detail is in `CLAUDE.md`'s tenant-behaviour list.

**And a `MANL` item behaves like any other.** Also live on STG, against style `TWA10134116` and SKU
`TWL10134402`: both approve, the SKU ranges, it takes a level-3 EAN13 barcode, and purchase order
`40003` was created against it with the line carrying the alphanumeric item. A duplicate number is
refused loudly - `Item already exists`, HTTP 400 - which is what makes a derived scheme safe to
collide on. That was the open risk under the POC and it is now closed.

**The document now accepts `ITEM_NUMBER` and `ITEM_NUMBER_TYPE`** - contract and rules in `CLAUDE.md`'s
inbound-document section. The deliberate decision, after some argument, is that **this layer does not
compose item numbers**: it accepts them. A composition rule here would have to know every caller's
numbering scheme, which is what `MAP.*` was and why it was retired.

Implemented and verified, 22 of 22 contract assertions passing, both numbering paths previewed:

| Change | Where |
| --- | --- |
| `ITEM_NUMBER` per size-curve row | `payload_pkg.c_size_curve`, the one projection |
| `ITEM_NUMBER` / `ITEM_NUMBER_TYPE` readers | `payload_pkg.document_item_number*` |
| Type sent to MFCS on parent and child create | `payload_pkg.append_parent_item`, `append_child_items` |
| Record rather than reserve | `orchestrator_pkg.assign_supplied_item_numbers` |
| Where numbers come from, decided in one place | `orchestrator_pkg.assign_item_numbers` |
| The whole rule set | `validation_pkg.validate_item_numbers` |
| `ITEM_NUMBER_TYPE` upper-cased at intake | `request_pkg.normalise_payload` |
| Preview stops advertising a reserve call that will not be made | `preview_pkg` |

**The empty-write-set guard could fail intermittently, and it is not this work's bug.** Worth reading
before trusting any single coverage run.

`CREATE_ITEM_SEASONS` built its usual 31-byte `{"collectionSize":0,"items":[]}` and the guard
`json_value(l_request_payload, '$.collectionSize' returning number null on error) = 0` stopped being
true, so the empty array went to MFCS, which answered `collection must have atleast one element`. The
request ended `PARTIALLY_COMPLETED` for a document that was never wrong. The same payload skipped
correctly on the next execution. It applies to every optional step - seasons, images, HTS and
reference items - on any request, and predates the item-number work.

**An earlier version of this section blamed a helper called `handles_own_item_numbers` and was wrong.**
It failed four runs in a row with that helper and passed two without, which looked conclusive and was
not: the same code shape later passed four runs in a row. The failure is intermittent, and four
consecutive occurrences were mistaken for determinism. Do not trust a single run of this suite to
attribute a cause.

The mechanism was then instrumented rather than guessed at. The guard was reading a **temporary** CLOB
(`dbms_lob.istemporary` confirms it) **two commits after it was built** - `set_step_status` and
`log_event` both commit between the mapper returning and the guard asking. `null on error` means a
failed read does not raise; it reads as "not empty" and the call goes out.

The fix is to ask once, against the payload as just built, before anything commits, and use the
answer:

```plsql
l_request_payload := payload_for_step(p_action_request_id, l_step);
l_collection_size := json_value(l_request_payload, '$.collectionSize' returning number null on error);
```

That is simpler than what it replaced and removes the window regardless of whether the temp-LOB
reading is the whole story. Null still means "no `collectionSize` key", which is the honest answer for
the reserve payload and correctly does not skip.

### Phase two - the review and approval gate, 2026-09-10

**App 103 is now the intended pipeline.** App 102 stays installed and checked in as reference and
fallback; nothing has been retired.

**Nothing reaches MFCS without two people.** A draft is worked on, submitted for review, then
approved, and only approval sends:

```
DRAFT --submit--> SUBMITTED --approve--> APPROVED --> MFCS --> COMPLETED / FAILED
```

Submitting validates, builds the document and **freezes it** on the draft. Approving replays that
frozen document rather than rebuilding it, so what the approver saw is what the tenant receives -
rebuilding at approval would make the approval decorative, and it is the same reasoning that makes
resume replay a stored payload. A submitted draft cannot be edited; `reopen_draft` takes it back to
DRAFT and discards the review, which is deliberately explicit because a change made behind an
approval is a change nobody approved.

**The review stage is semi-frozen.** Order quantities stay editable on the submit modal - they are
what a review is usually about - and everything else is fixed. The modal's grid saves the quantities
*before* `submit_for_review` builds, so the frozen document carries the reviewed numbers. Proven:
a draft submitted after changing 6 to 12 froze `SKU_QTY 12`.

Nine pages. **Capture** (page 2) replaced Create Style: a mode at the top chooses *Style only* or
*Order and Style*, the order section appears only for the latter, and five grids beneath capture
UDAs, barcodes, seasons, images and tariff codes. **Drafts and Approvals** (5) lists every draft with
its status. **Submit for Review** (6) and **Approve** (7) are modal dialogs showing the same tabs -
style, order, SKUs and quantities, UDAs, barcodes, seasons and tariffs - with a frozen-document tab
on the approve side. **Execution** (8) is app 102's page 4 ported: every step, its status, the
endpoint, the HTTP status and both payloads, read from `STEP`, `ATTEMPT` and `EVENT_LOG`. **Amend
Order** (9) reads an order from MFCS and seeds an editable draft from it.

New tables: `POC_DRAFT_UDA`, `POC_DRAFT_SKU_UPC`, `POC_DRAFT_SEASON`, `POC_DRAFT_IMAGE`,
`POC_DRAFT_HTS`, and `POC_APPROVER` for the submitter and approver lists (invented data). Drafts
gained an `OPERATION_NAME`, an `ORIGIN` and the order fields.

**`ORIGIN` is why an amended draft does not get recomposed.** A draft seeded from MFCS carries
numbers the tenant assigned; `refresh_composition` returns immediately for `AMENDED`, because
recomposing them would invent a different style than the one being amended.

**Proven live on STG, all through the gate:**

| Flow | Result |
| --- | --- |
| Style only | `31551120` from CLARKS DESERT CROSBY + Burgundy 120, submitted by Priya Naidoo, approved by Tom Fletcher, COMPLETED |
| Order and Style | `31566090` + **order 40004**, quantities adjusted at review, COMPLETED |
| Amend Order | order 40004 read back and seeded as draft 83 with its two lines, real size diffs and descriptions |
| Gate | approving a DRAFT is refused: `ORA-20960: Draft 61 is DRAFT, and this action needs it to be SUBMITTED` |

**The SKU description gap is closed.** The contract gained `ITEM_DESCRIPTION` at the root and per
size-curve row, `payload_pkg` resolves it in one place, and `APPROVE_ITEMS` no longer overwrites
every child description with the style's. `31551120`'s SKUs read back from MFCS as
*CLARKS DESERT CROSBY Burgundy **S*** and ***M*** - the size description the specification asks for,
where before the size was lost entirely.

Coverage 20 of 20, contract 22 of 22, zero invalid objects.

### The Office POC console - app 103, `Office Style Composer`

Four pages: **Home** (reference counts as cards, a worked example of the composition, recent drafts
with the item number linking through to the viewer), **Create Style** (the capture), **Style Viewer**
and **Reference Data** (colours and codes editable, styles read-only with a search).

**Style Viewer** reads a style live from MFCS through `browse_pkg.get_style(item, 'Y')` - once, in a
before-header process, into the `MFCS_STYLE` APEX collection - and every region then queries that
collection rather than calling the tenant again. Style attributes sit in display-only page items;
SKUs, sourcing, barcodes, seasons/images/tariffs and the raw document are tabs beneath. The header
shows `resolved.source`, which distinguishes "this style has no SKUs" from "the feed had not
published them yet". Verified live against `31550080`: 3 SKUs, sourcing, and the header fields all
render, with the style read back as `MANL`.

Its tables and its composition package are the **calling system**, not the integration layer:

| Object | Holds |
| --- | --- |
| `POC_STYLE_MODEL` | 13,693 styles, generated from `docs/dataSamples/uat_uda.json` (UAT UDA 66040) |
| `POC_SUPPLIER_COLOUR` | 29 invented colours - UDA 56038 is free-form, so the list is ours |
| `POC_SUPPLIER_COLOUR_CODE` | 38 codes, each belonging to a colour, so the screen cascades |
| `POC_STYLE_DRAFT` / `_SKU` | one capture and its size curve, with the composed values stored |
| `poc_style_pkg` | the composition rule, and the call to `api_pkg` |

`poc_style_pkg` composes and `api_pkg` accepts. The document carries `ITEM_NUMBER` and
`ITEM_NUMBER_TYPE: MANL`, which is the whole point of the split.

**Proven live on STG.** Draft 1 composed `31550080` from style `31550` *CLARKS DESERT BOOT* and
colour code `080` *Sky Blue*, submitted through the same package path the page's button uses, and
completed all 14 steps. `itemDetail` reads the style back approved at level 1 with three approved
level-2 SKUs `31550080992/993/994`, diff1 `08610`, diff2 the size differentiator.

**A gap between the specification and what actually reaches MFCS, found by reading the payloads
back.** The SKU *number* is caller-composed and arrives intact. The SKU *description* is not:

- The document has no per-SKU description field, so `payload_pkg.append_child_items` builds one as
  `SOURCE_STYLE_REF || ' ' || SKU_SIZE`. That sends `CLARKS DESERT BOOT Sky Blue 992` - the size
  *differentiator id*, where the specification asks for the size *description*, `S`.
- `APPROVE_ITEMS` then sends the style's description for every item, so the child description is
  overwritten with `CLARKS DESERT BOOT Sky Blue` and the size is lost entirely.

`poc_style_pkg.compose_sku_desc` already builds the right string and stores it on the draft, where
the console displays it. Nothing carries it to MFCS. Closing this is the same architectural move as
`ITEM_NUMBER`: give the contract an `ITEM_DESCRIPTION` at the root and one per `SIZE_CURVE_DETAIL`
row, have the mappers prefer them when present, and stop `APPROVE_ITEMS` overwriting a description it
was not asked to change. Until then, do not report the SKU description rule as working.

### Still to do before the POC rests on this

**The SKU description rule is now honoured end to end** and no longer belongs on this list.

**Preview shows `"item": null` for a caller-numbered request.** The numbers are in the document and
could be shown. Making `payload_pkg.resolve_sku` and `request_style` fall back to the document does
it, and was written and working - but it puts a `json_table` query per SKU per mapper into the shared
execution path, which wants its own coverage runs rather than one. Preview-local substitution avoids
the execution path entirely and is the safer shape. Not a regression: the reserve path has always
previewed as `null`.


**The UDAs the Office rules assume exist on UAT, and STG is missing exactly four.** Both tenants read
live on 2026-09-10. STG publishes **23** UDAs; UAT publishes **27** and is a strict superset - nothing
on STG is absent from UAT. The four to have loaded onto STG:

| UDA | Display | Data type | Description | Values |
| --- | --- | --- | --- | --- |
| **66040** | `LV` | ALPHA | **Style** | **13,693** |
| **56038** | `FF` | ALPHA | **Supplier Colour** | 0, free-form |
| **61038** | `FF` | ALPHA | **Supplier Colour Code** | 0, free-form |
| 56039 | `DT` | DATE | Launch Date | 0, date |

`Launch Date` is not in the Office rules but belongs to the same set and is free to carry along.

**Style is exactly the LV UDA the rules described**, and its values settle the numbering question: all
13,693 are numeric, all **exactly five digits** (`10000`-`99999`), all distinct, each with a description
that reads like a model name (`CLARKS DESERT BOOT`, `ENDEAVOUR CHELSEA BOOT`). A fixed-width model
component therefore needs no padding - it already is one.

**Supplier Colour is `FF`, not `LV`, and that is why the rules put it in RDS.** A free-form UDA has no
value list in MFCS, so there is nothing there to maintain and nothing to validate against - which is
exactly what makes "let the planner create one on the fly" workable. It also comes as a **pair**:
`Supplier Colour` for the name and `Supplier Colour Code` for the number, matching the rules' split
between what composes the item *number* and what composes the *description*. Both are written to the
item as text: per the UDA-write note in `CLAUDE.md`, `FF` carries `udaText`, `LV` carries `udaValue`
and `DT` carries `udaDate`, all of which the existing mapper already sends.

**Nothing here can create a UDA.** The 323-path spec has `foundation/uda` as **GET only**; `item/uda/*`
associates an existing UDA with an item and cannot define one or add a value. So these four have to be
loaded inside MFCS - spreadsheet upload or the UI - by whoever owns the tenant. That is the ask.

**Loading Style onto STG has a size consequence worth knowing about.** UAT's UDA feed is **2.2MB**
against STG's 112KB, almost all of it UDA 66040's values. `master_pkg.load_udas` parses the whole
document in memory and stores each UDA's raw JSON in `MASTER_DATA.ATTRIBUTES`, so the Style row alone
will hold roughly 2MB. `ATTRIBUTES` is a `CLOB`, so this stores rather than fails, and the default
`p_limit` of 500 covers 27 UDAs - but the refresh will gain about 14,000 `UDA_VALUE` rows and should be
watched the first time it runs.

**What is left of the ambiguity problem is the colour half.** The model component is a fixed five
digits, but `Supplier Colour Code` is free-form, so its width is whatever RDS decides. Fix it there, and
keep a non-numeric character in the composed number so a derived style number can never collide with
one of the tenant's own 9-digit auto-generated ones.

**Supplier Colour is not the MFCS colour diff.** A style would carry both: the diff that *defines* its
SKUs, which must be a real diff in the parent's `RMS_ALL_C` group, and the supplier colour that
composes the number and description. Conflating them would be easy and expensive.



## Where things stand

The integration runs against the **real MFCS dev tenant** and nothing else. Simulators, mock modes and
the `MFCS_CLIENT_MODE` switch were removed — if you find a reference to them, it is stale.

| Area | State |
| --- | --- |
| `CREATE_STYLE`, `CREATE_ALL` | Proven end to end against the tenant |
| `MODIFY_STYLE` | **Completed live 2026-08-22**, all seven steps |
| `CREATE_ORDER` | **Completed live 2026-08-22**, all eleven steps, order 25012 created and verified |
| `MODIFY_ORDER` | **Proven live 2026-08-22 both directions**: quantities, colour switch with line creation + cancellation, and switch-back, all verified by read-back |
| Missing-SKU generation | **Proven live 2026-08-22**: created two children under an existing style, verified by read-back |
| Failure / resume paths | 20 of 20 passing, fault-injected against the real tenant (re-verified 2026-08-22 after the batch window closed) |
| Console (`ui/`) | Build, Activity, Styles & orders, Master data, MFCS spec, **How it works** (clickable end-to-end flows) |
| APEX console | App 102 `MFCS Controller` installed in workspace `TW_TEST`, parsing schema `MFCS_INTEGRATION` |
| Item ranging | On, using virtual warehouse 19271 |
| Non-merchandise costs | `NON_MERCH_COSTS` → order `expenses`, validated and previewing; not yet sent live |

| UDAs | **Proven live 2026-09-01.** Captured in the console, sent, read back |
| Barcodes (level-3 UPCs) | **Proven live 2026-09-01.** Captured in the console, sent, read back |
| `BRAND` | Sent and silently dropped by the tenant. **Does not work** |
| Seasons, images, tariff codes | **Proven live 2026-09-01.** Captured in the console, sent, read back |
| Console end to end | **Proven live 2026-09-01.** APEX draft through to MFCS, style 100150356 |
| `MAP.*` config | **Retired 2026-09-01.** Lists and validation read `MASTER_DATA` |
| APEX pages | 1 Home, 3 Create/Edit, 4 Activity, 5 Browse, **10 Style Capture**, **20 Style Explorer** |

Environment: MFCS STG `https://rex-npe.retail.eu-frankfurt-1.ocs.oraclecloud.com/rgbu-rex-truw-stg3-mfcs`
and UAT `.../rgbu-rex-truw-uat3-mfcs`; the IDCS token host is different again. The database is
**mdutilstst01**, Oracle 23.26.2.0.0, PDB `FREEPDB1`, schema `MFCS_INTEGRATION` — *not* the `adb-free`
container older notes describe. Connect with `deploy/mdutils/sql.sh`.

**If the coverage suite is failing, check the token before suspecting the code.** A stale token makes
every MFCS step fail with `-20950` and the suite reports roughly half its assertions failed. That is
not a regression. `GET /token-status` says so in one line.

**Bearer tokens last one hour.** Most "nothing is working" moments are an expired token — the console
header shows remaining validity, and `GET /token-status` decodes it.

## Session of 2026-09-01 — what changed

Fifteen commits, all pushed. Ordered by how much each alters the picture.

**The inbound contract settled.** `PLMSizeCurveDtl` became `SIZE_CURVE_DETAIL`, and
`request_pkg.normalise_payload` accepts either spelling at intake — before the payload is
hashed, stored or validated, so resume replays a canonical document. `DEPARTMENT`, `CLASS` and
`SUBCLASS` are numbers. New optional keys: `STYLE_UDAS`, `SKU_UPCS` (inside each size-curve
row), `STYLE_SEASONS`, `STYLE_IMAGES`, `STYLE_HTS`, `BRAND`. `SKU_WIDTH` is no longer required.

**`MAP.*` is retired.** It was two things wearing one name: a translation table and a whitelist
maintained alongside master data and free to disagree with it — which is how `MAP.COLOUR.BLACK`
came to offer a colour the tenant rejects, after an item number had been burned. Every front end
now sends the tenant's own identifiers, so the translations had nothing left to do, and the
whitelists moved to `MASTER_DATA`. 340 config rows deleted. One translation survives because it
is not a naming difference: `payload_pkg.virtual_location` maps a physical warehouse to its
virtual one, derived from the warehouse feed rather than a hand-maintained row.

**Five attribute types now reach MFCS, all proven live**: UDAs, barcodes (level-3 reference
items), seasons, images and tariff codes. Style `100150305` carries all five, verified by
read-back.

**The console path is proven end to end.** Request `APEX-20260901212130632` completed from an
APEX draft through to MFCS — style `100150356`, 17 steps, 20 calls.

**Master data is populated and is now the single source.** 23 UDA definitions with 750 values,
244 brands, 60 suppliers, 250 countries, 12 warehouses, 215 colours and 29 sizes with
descriptions from the front-end exports. `master_pkg.load_udas` and the fixed warehouse loader
were both storing nothing before today.

**Two new APEX pages**, leaving 3, 4 and 5 untouched: **10 Style Capture** and **20 Style
Explorer**.

## Outstanding, in the order I would take it

### A. Items are created with no price
Everything we create reads back `unitRetail: 0`; a real UAT item reads `85`. We send
`originalRetail` and it does not reach the field the tenant treats as the price. Consistent with
`ENDPOINT.INITIAL_RETAIL` being a placeholder with no matching write service. **This is the
largest functional gap** — a style in MFCS priced at zero is not a usable style. Needs a decision
on what Office expects before it can be built.

### B. The differentiator group is not selectable
The parent's `diff1`/`diff2` come from `MFCS_PARENT_DIFF1_GROUP` and `MFCS_PARENT_DIFF2_GROUP`
config, hardcoded to `RMS_ALL_C` and `ALL`, and nobody chooses them per style.

No longer blocked on data: STG now publishes `foundation/diffgroup` (12 groups with their members,
loaded 2026-09-28). And the fix is no longer a group picker. Under the consultant's style/colour
model the L1 carries the document's colour itself in `DIFF_1` and a chosen size group in `DIFF_2`,
so this item is replaced by the item-structure change: a `SIZE_GROUP` on the document, the colour
in `DIFF_1`, and validation that every SKU's size belongs to the group.

### C. Non-merchandise costs have no capture
`NON_MERCH_COSTS` is validated and previewed by the backend and maps to the order's `expenses`,
but neither console has a field for it, and it has never been sent live.

### D. `BRAND` is accepted and silently dropped
`items/create` takes `brandName`, answers SUCCESS, and the item reads back with no brand while
UDAs written in the same call are present. The brand code was checked against the tenant's own
246, so it is not a bad value. `items/update` as a second attempt hit post-approval record
locking and settled nothing. Parked by agreement; not exposed in either console, because offering
a field that does nothing is worse than not having it.

### E. Only `CREATE_ALL` has run from the console
The console offers all five operations. `CREATE_STYLE`, `CREATE_ORDER`, `MODIFY_STYLE` and
`MODIFY_ORDER` have never been driven from it. Related and unproven: on the modify paths
`CREATE_REFERENCE_ITEMS` resolves to `items/update`, and whether that service accepts a level-3
item has never been tested.

### F. HTS assessments are not sent
The tenant's own rows carry `componentId DTY7AGB` against `computationValueBase VFDGB` with duty,
expense and ALC flags. The tariff code is useful without them; the assessments need someone who
knows the customs side.

### G. The capture page is reorganised, not redesigned
Page 10 groups 27 header fields into four titled sections and is derived from page 3. Real polish
— a summary card, a wizard flow, a popup colour picker over the 48,624 differentiators rather
than a select list — is a deliberate piece of design work still to do. The `popupLov` donor and
the syntax are recorded in the APEXlang skill.

### H. Two directories are untracked pending a decision
`docs/dataSamples/` (includes 60 real suppliers with addresses) and `docs/foundationExports/`
(2.3 MB, with exact duplicates: `Differentiators` twice, `HTS Definition` twice, `Phases` three
times). Neither is in git.

## Older outstanding work

### 1. Exercise the remaining edges of order-line sync

The line services are wired and proven. `SYNC_ORDER_LINES` (MODIFY_ORDER, seq 105) reads the
order, updates/creates/cancels this style's lines, and verifies by read-back — quantities,
a full colour switch with cancellation (`S`), a reduction (`B`), and resurrection of a cancelled
line have all run live on order 25012. Semantics worth re-reading before touching it:
`quantityCancelled` is cumulative-absolute and is deliberately never sent; `quantityOrdered` is
authoritative and `quantityOrdered:0` + `cancelInd` + `cancelCode` is a cancellation.

What has not been exercised: an order carrying lines from more than one style (the scoping is
coded — only the document's style's lines are candidates for cancellation — but never run),
`MFCS_ORDER_LINE_ABSENT_ACTION='LEAVE'`, and a colour switch where the new colour is not in the
parent's diff group (rejected loudly by MFCS: the diff must be a member of the parent's group —
`BLACK` failed, `08621` worked; adding members to a diff group is untested territory).

### 1a. Every operation now sends its whole write set

Worth stating because it is a design rule, not an implementation detail. `MODIFY_STYLE`,
`CREATE_ORDER` and `MODIFY_ORDER` share one seven-step style sequence — SKU check, hierarchy,
sourcing, country of manufacture, UDAs, ranging, approval — and the order operations place the order
on top of it. Nothing is skipped for looking unchanged: the inbound document states what the style
should be, not what changed, and MFCS answers a no-op write with SUCCESS, so an omission would be
silent. Do not reintroduce conditional sending.

Getting there fixed four things, each found by running it:

- `items/update` refuses without `STORE_ORD_MULT`, even for a description-only change.
- `suppliers/update` refuses without `DIRECT_SHIP_IND`, then `INNER_NAME`. All three packaging names
  are now sent; the valid values are the tenant's own code types `INRN`, `CASN`, `PALN`.
- `countriesOfManufacture/create` cannot be replayed — it answers an existing row with "already
  exists". Existing styles use the `update` service.
- `ORA-29273` was classified as a failure while MFCS had actually created the purchase order. A
  transport error is an *unknown* outcome; `client_pkg` now classifies on SQLCODE and lets
  `recovery_pkg` resolve it by correlation ID.

### 2. Point the console's dropdowns at the code details (loading done)

`master_pkg.refresh_all` now loads `administration/operations/codes` — **797 code types, 7,049 rows** —
plus banners and channels. Each value is stored as `CODE_<codeType>` with the code type as
`parent_code`, and `CODE_TYPE` lists the types themselves.

What remains is using them: the console's fixed-value fields (order type, status, freight terms, cost
basis, expense components) still read from `CONFIG` or free text. Point them at `CODE_*` instead.

### 4. Non-merchandise costs, end to end

The mapping is in and previews correctly. It has not been sent to MFCS, so the component codes
(`FREIGHT`, `DUTY`, …) have not been validated against what the tenant actually accepts. Expect the
first live attempt to reveal the valid component list.

## What Office items actually look like, and what we do not build — 2026-09-01

Three real item documents (a style, a SKU and its barcodes) were compared against a style this layer
created. Samples are cached in `docs/dataSamples/`.

**The shapes match.** `foundation/item` returns 118 keys on UAT and 125 on STG, and every UAT key exists
on STG — STG is a superset, adding the company/division/group hierarchy. `itemDetail` rows are byte-for-
byte the same shape at all three levels, 25 keys each. Nothing about what we create is structurally
wrong.

**What a real item carries that ours does not:**

| | ours | theirs |
| --- | --- | --- |
| `itemUda` | 3 (written by hand in a probe) | 13 |
| `referenceItem` | 1 (written by hand in a probe) | 2, one primary |
| `itemSeason` | null | `seasonId 1, phaseId 1, sequenceNo 1` |
| `itemImage` / `primaryImageUrl` | null | Amplience CDN, `imageType T` |
| `hts` | null | `6402993900` GB←DE, with `assessments` |
| `brandName` / `brandDescription` | null | `18` / `Birkenstock` |

Both mechanisms behind the first two rows are now proven live — see
`docs/mfcs-actual-call-flow.md`. Neither has a step in the graph yet.

**One defect, not a gap.** Our SKU reads back `unitRetail: 0` where the real one reads `85`. We send
`originalRetail` and it does not reach `unitRetail`, which is where the tenant keeps the effective
price. Everything this layer has created is priced at zero. Confirm what Office expects before deciding
whether that matters.

**Foundation data is no longer the blocker it was.** STG now publishes `uda` (23 definitions with their
values), `supplier`, `store` and `warehouse`. UAT publishes all of those plus `diffid` (380),
`diffgroup` (13, each naming its member diffs), `difftype` and all three `merchhier` levels. The
`MAP.*`-and-derive-from-item-feed approach was a workaround for empty feeds; on UAT it is no longer
needed.

**The bottleneck is now inbound.** We cannot send UDA values, barcodes, seasons or HTS codes that the
Office document has no room for. The MFCS-side work is mapper work in shapes we already run; agreeing
the inbound contract is the critical path.

## Known gaps that are not our bugs

**Most foundation services are empty publish queues.** `merchhier/*`, `diffid`, `difftype`,
`diffgroup`, `supplier`, `store`, `warehouse`, `uda` all return HTTP 200 with zero rows, and
`since`/`before` does not change it. Only `item/brands`, `item/foundation/seasons`, `orghier`,
`banners`, `channels`, `codes` and `item/location` return foundation rows directly. This is why the
master-data cache derives hierarchy, differentiator and supplier values from the item and order feeds.

**`ENDPOINT.INITIAL_RETAIL` is a placeholder.** No matching write service exists in the tenant spec, so
`FEATURE_INITIAL_RETAIL_YN` stays `N`.

**No offline test coverage.** The suites that ran without a tenant were removed with the simulators.
Everything now requires a live token, and the coverage suite creates real records by design. Rebuilding
offline coverage against recorded fixtures is unstarted.

## Things that will mislead you if you forget them

- **The tenant serves more than its OpenAPI document lists.** `RmsReSTServices/services/private/Item/itemDetail`
  is not in the spec but is the only way to get a style's children in one call. "Not in the spec" is not
  the same as "not available".
- **Unknown query parameters are silently ignored**, returning an unfiltered feed that looks like a
  working filter. It is `deptId`, not `dept`. There is no `itemParent` filter.
- **MFCS can return `SUCCESS` and do nothing** — proven with the diff change. Verify writes by reading
  back, not by trusting the response.
- **List endpoints are publish/delta feeds**, not queries. They show approved and published records
  only, and lag by a few seconds.
- **Resume replays the *stored* payload.** A request that failed because of a bad value in that payload
  cannot be rescued by resuming; it needs a fresh request.
- **`ENSURE_STYLE_SKUS` is the exception to that**, deliberately. It stores no payload: it re-reads the
  style on every entry and acts on what it finds, so a resume creates only what is still missing.
- **`foundation/item/{item}` is a feed read.** It answered 404 for a style created and approved minutes
  earlier, while `itemDetail` returned it in full. Anything that has to work on a freshly created
  record must not be built on the feed.
- **`itemDetail` is a third vocabulary.** Not the item feed's names and not the write services': it says
  `classAttribute`, `itemDesc`/`shortDesc`, `primarySuppInd`, `originCountryId`, `suppPackSize`.
  `sku_pkg.style_attributes` translates so callers see one set of names.
- **The update services want the whole record.** `items/update` demands `STORE_ORD_MULT` even when only
  a description changed; `suppliers/update` demands `DIRECT_SHIP_IND`, then `INNER_NAME`. The create
  services default all three.

## Running things

```bash
# Install from zero (schema owner)
@deploy/adb-free/install.sql

# Fault-injected failure and resume coverage - creates real tenant records
@tests/resume_coverage_tests.sql

# Console
cd ui && npm install && npm run dev      # http://localhost:5173
```

`deploy/adb-free/` also holds the schema/ACL setup, a connectivity probe, endpoint sweeps and
`set_token.sql` for loading a Postman-issued bearer token.

```bash
# Seed APEX LOV foundation data after setting/updating the token
@deploy/adb-free/09_refresh_master_data.sql
```

APEX source lives in `apexlang/mfcs-controller`. `apex validate` and `apex import` work with the
installed SQLcl, but `apex export` / `apex generate` currently throw a SQLcl Java
`Path.of(null)` error in this Windows shell. Upgrading SQLcl is convenience work, not a blocker for
deploying the checked-in APEXlang source.
