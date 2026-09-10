# The APEX consoles

Conventions and state for the two APEX applications in this repository. The *how* of editing
APEXlang lives in `.claude/skills/apexlang-coding-agent/SKILL.md`, which is deliberately generic and
knows nothing about MFCS; everything MFCS-specific is here.

## The two apps

| App | Name | Export | Role |
| --- | --- | --- | --- |
| **102** | MFCS Controller | `apexlang/mfcs-controller` | The original console. Kept installed as reference and fallback |
| **103** | Office Style Composer | `apexlang/office-style-poc` | The intended pipeline: compose, capture, review, approve |

Both are in workspace **`TW_TEST`**, parsing schema **`MFCS_INTEGRATION`**, on `mdutilstst01`.

```bash
# The connection wrapper for every SQLcl call in this repo
deploy/mdutils/sql.sh script.sql
```

```sql
apex validate -input "<abs path>\apexlang\office-style-poc" -workspace TW_TEST
apex import   -input "<abs path>\apexlang\office-style-poc" -workspace TW_TEST -id 103 \
              -schema MFCS_INTEGRATION -name "Office Style Composer"
apex export   -applicationid 102 -exptype APEXLANG -dir "<abs path>\apexlang\_export_102"
```

Exporting 102 and diffing it against the checked-in copy is how changes made in Builder get picked
up:

```bash
diff -rq apexlang/mfcs-controller apexlang/_export_102/a14020250319160406704102
```

## Conventions both consoles follow

- **Do not copy StyleMan behaviour blindly.** StyleMan is visual inspiration only; the flow rules
  come from this repo's backend packages.
- **Lists of values read `MASTER_DATA`, which is what the tenant holds.** `MAP.*` config was retired
  on 2026-09-01: it was a whitelist maintained alongside master data and free to disagree with it,
  which is how a colour the tenant would reject came to be offered. Validation checks the same master
  data the lists read, so the console cannot offer a choice the backend then refuses.
- **`SKU_SIZE` is a differentiator ID, not a display size.** The list shows `7 - 070` and returns
  `070`. Sending a description would be ambiguous - eight size descriptions on this tenant map to
  more than one differentiator.
- **`COLOUR` is style/colourway level.** Do not add SKU-level colour unless the backend contract
  changes to support several colourways per request. Note this is the MFCS *differentiator*, which is
  a different thing from app 103's supplier colour - see below.
- **The delivery-location list offers virtual warehouses only.** MFCS refuses ranging against a
  physical location at hierarchy level W, so offering one offers a choice that fails several steps
  later. A read of an existing order reports the *physical* location, and
  `payload_pkg.virtual_location` translates on the way out.
- **For order creates, expose and default** `NOT_BEFORE_DATE`, `NOT_AFTER_DATE`, `OTB_EOW_DATE`,
  `EARLIEST_SHIP_DATE` and `LATEST_SHIP_DATE`. `OTB_EOW_DATE` must fall on the configured retail
  week-ending day.
- **Style-level detail is captured once** and written to the style and every SKU by the backend:
  UDAs, seasons, tariff codes. Images are the exception - MFCS cascades those itself and rejects the
  child's copy. There is no SKU-level capture for any of them.
- **MFCS list and browse endpoints lag newly created records**, and `foundation/item` is served from
  a cache that can be a minute behind. Do not use them as the only success signal.

## Where state lives

Written by the backend for every request, whichever console started it:

- `REQUEST` - the registered integration request and its stored document
- `STEP` - the ordered step graph and each status
- `ATTEMPT` - endpoint, method, request and response payloads, HTTP status per MFCS call
- `EVENT_LOG` - an autonomous trail that survives a failure

App 102's capture state:

- `UI_DRAFT` and its children `UI_DRAFT_SKU`, `UI_DRAFT_SKU_UPC`, `UI_DRAFT_UDA`,
  `UI_DRAFT_SEASON`, `UI_DRAFT_IMAGE`, `UI_DRAFT_HTS`

App 103's, which is the calling system rather than the integration layer:

- `POC_STYLE_MODEL`, `POC_SUPPLIER_COLOUR`, `POC_SUPPLIER_COLOUR_CODE` - the reference lists
- `POC_STYLE_DRAFT` and `POC_STYLE_DRAFT_SKU` - one capture and its size curve
- `POC_DRAFT_UDA`, `POC_DRAFT_SKU_UPC`, `POC_DRAFT_SEASON`, `POC_DRAFT_IMAGE`, `POC_DRAFT_HTS`
- `POC_APPROVER` - who may submit and who may approve

App 102 page 20 (Style Explorer) and app 103 page 8 (Execution) both read `STEP`, `ATTEMPT` and
`EVENT_LOG`, and are the quickest way to see what a request actually did.

## App 103's own rules

- **`poc_style_pkg` composes; `api_pkg` accepts.** The composition rule - style number plus supplier
  colour code, style description plus colour name - belongs to the caller. A rule in the controller
  would have to know every caller's scheme, which is what `MAP.*` was.
- **Supplier colour is not the MFCS colour differentiator.** The diff defines the SKU and must be one
  the tenant holds; the supplier colour composes the number and the description. A style carries
  both, and merging them would be easy to do by accident.
- **`ORIGIN` decides whether numbers get recomposed.** `COMPOSED` drafts have their item numbers
  rebuilt from the style and colour on every save; `AMENDED` drafts, seeded by reading MFCS, do not -
  recomposing them would invent a different style than the one being amended.
- **Nothing reaches MFCS without a review and an approval.** Submitting freezes the document;
  approving replays the frozen one. Order quantities stay editable during review and are saved before
  the document is built, so the frozen document carries the reviewed numbers. See
  `docs/status-and-next-steps.md` for the full state machine.

## Reading live MFCS data on a page

`browse_pkg.get_style(item, 'Y')` returns the style with its children and puts its own findings on
**`$.items[0].resolved`**: `skus` (each child read in full, not the thin `itemDetail` version),
`skuCount`, and `source`, which says whether the children came from `itemDetail` or from a feed scan.
`browse_pkg.get_order(order_no, 'Y')` adds `resolved.style` and `resolved.colour` at order level, and
on each line `resolved.diff1`, `diff2`, `displaySize` and `itemDescription`.

**Show `source` on the page.** It is the difference between "this style has no SKUs" and "the feed had
not published them yet".

Read once in a before-header process into an APEX collection and let the regions query that, rather
than calling `browse_pkg` from each region - the generic pattern and its pitfalls are in the skill.
