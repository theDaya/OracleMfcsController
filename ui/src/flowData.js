// Everything the "How it works" tab renders. Content lives here as data so
// keeping the picture current is an edit to this file, not to layout code.
//
// Accuracy contract: step sequences mirror step_pkg.initialize_steps, the
// endpoint/method/mapper triples mirror orchestrator_pkg.resolve_step, and the
// tenant behaviours quoted here are the proven ones from
// docs/mfcs-actual-call-flow.md. If you change those, change this.

// ---------------------------------------------------------------------------
// The end-to-end journey every request takes, regardless of operation.
// ---------------------------------------------------------------------------
export const PIPELINE = [
  {
    id: 'document',
    title: 'Office document arrives',
    pkg: null,
    blurb: 'One JSON document stating what a style or order should now be',
    detail:
      'PLM/Office sends a single document: identity (ACTION_REQUEST_ID, OPERATION_NAME, source ' +
      'references), the merchandise fields (department, class, colour, supplier, cost, retail), the ' +
      'size curve (SIZE_CURVE_DETAIL - one row per size/width), and order fields when an order is ' +
      'involved. It is a statement of desired state, not a diff: the layer assumes everything in it ' +
      'may have changed. The console’s Build tab constructs exactly this document and nothing more - ' +
      'all downstream logic lives in the database.',
    gotchas: [
      'PLM does not know about SKUs. It names a style and a colour; resolving or creating the actual child items is this layer’s job.',
    ],
  },
  {
    id: 'ords',
    title: 'ORDS handler',
    pkg: 'ords_util_pkg',
    blurb: 'POST /mfcs/v1/transactions → api_pkg, response streamed back in chunks',
    detail:
      'The ORDS module (database/30_ords) is deliberately thin: each handler calls one api_pkg ' +
      'procedure and emits whatever status and body it returns, through ords_util_pkg.emit_json. ' +
      'The chunked emit exists because htp.prn takes a VARCHAR2 - a response over 32KB would ' +
      'otherwise die as an opaque HTTP 555.',
    gotchas: [],
  },
  {
    id: 'api',
    title: 'api_pkg.submit_transaction',
    pkg: 'api_pkg',
    blurb: 'The public entry point: validate, register, execute, respond',
    detail:
      'The only package ORDS calls for transaction work. submit_transaction orchestrates the whole ' +
      'lifecycle: validation first (so a bad document is rejected with zero side effects), then ' +
      'idempotent registration, then execution. Whatever happens, the response is the canonical ' +
      'status document built by request_pkg.build_status_response - status, completed steps, failed ' +
      'step, generated identifiers, errors.',
    gotchas: [],
  },
  {
    id: 'validate',
    title: 'validation_pkg',
    pkg: 'validation_pkg',
    blurb: 'Every problem found, not just the first - before anything is stored or sent',
    detail:
      'Field-level checks on the raw document: required fields per operation, types, dates, master-data ' +
      'translations. Rules MFCS only enforces late are checked here early: OTB_EOW_DATE must fall ' +
      'on a Sunday, and MFCS would only tell you at order create - by which point a style exists ' +
      'and an order number is burned. A failed validation returns HTTP 422 with a JSON array of ' +
      'every {FIELD, CODE, MESSAGE} found.',
    gotchas: [
      'OTB_EOW_DATE must be a Sunday (the retail week end). Enforced here so it fails before any MFCS call.',
      'With SKU generation on, an unresolvable SKU_ID is not an error here - ENSURE_STYLE_SKUS consults the tenant, which knows more than this database’s memory.',
    ],
  },
  {
    id: 'register',
    title: 'request_pkg: idempotent registration',
    pkg: 'request_pkg',
    blurb: 'NEW → execute · DUPLICATE → replay stored outcome · CONFLICT → 409',
    detail:
      'The document is hashed (SHA-256). A new ACTION_REQUEST_ID registers and executes. The same ' +
      'id with the same hash is a DUPLICATE: the stored outcome is replayed without touching MFCS. ' +
      'The same id with a different hash is a CONFLICT: HTTP 409, nothing happens. This is what ' +
      'makes retries safe for the caller - sending the same document twice can never create twice.',
    gotchas: [],
  },
  {
    id: 'steps',
    title: 'step_pkg: the full plan, written before anything runs',
    pkg: 'step_pkg',
    blurb: 'Every step for the operation goes into STEP as PENDING, in sequence',
    detail:
      'initialize_steps writes the operation’s whole step graph up front. The design rule: every ' +
      'operation sends its whole write set, every time. The document says what the style should be, ' +
      'not what changed - and MFCS answers a write that changes nothing with SUCCESS, so a step ' +
      'skipped for "looking unchanged" would never announce its omission. Structure is code, values ' +
      'are CONFIG; the graph is not table-driven on purpose.',
    gotchas: [
      'An order operation carries the full style write set too: ordering is a statement about the style (cost, country, supplier), not only about the order.',
    ],
  },
  {
    id: 'loop',
    title: 'orchestrator_pkg.execute_request',
    pkg: 'orchestrator_pkg',
    blurb: 'Loop: first runnable step → resolve → build payload → call → journal',
    detail:
      'One loop asks step_pkg.first_runnable_step for the lowest-sequence step still PENDING, ' +
      'FAILED or OUTCOME_UNKNOWN, resolves it to an endpoint + method + mapper through ' +
      'resolve_step (one case statement, so the three can never disagree), builds the payload, ' +
      'sends it through client_pkg, and marks the outcome. Resume is the same loop: whatever has ' +
      'not succeeded runs next. There is no separate resume code path to drift.',
    gotchas: [],
  },
  {
    id: 'payload',
    title: 'payload_pkg: the MFCS write contract',
    pkg: 'payload_pkg',
    blurb: 'Every request body MFCS receives is built here, statically wired',
    detail:
      'One mapper per call shape, reading the stored document plus CONFIG defaults and master-data ' +
      'translations. orchestrator_pkg calls build_request statically, so a missing mapper is a ' +
      'compile error rather than a runtime surprise. The size-curve projection is defined once ' +
      '(c_size_curve) and every reader loops it. Mappers speak MFCS’s write vocabulary only - the ' +
      'read side uses different field names for the same data.',
    gotchas: [
      'Order read/write vocabularies disagree: read gives physicalQuantityOrdered / originCountryId, write wants quantityOrdered / originCountry.',
    ],
  },
  {
    id: 'client',
    title: 'client_pkg: the only outbound path',
    pkg: 'client_pkg',
    blurb: 'Credentials, HTTP, attempt journalling, failure classification',
    detail:
      'The single place that resolves the bearer token and makes an outbound call - a second HTTP ' +
      'path is how a stale token once survived in one code path and not another. The token is read ' +
      'from SECRET on every call, never cached (ORDS pools sessions; a cached credential outlives ' +
      'its request). Every call is bracketed by begin_attempt / complete_attempt with a fresh ' +
      'correlation id, which is what makes ambiguous outcomes recoverable.',
    gotchas: [
      'Bearer tokens last one hour. Most "nothing works" moments are an expired token: every step fails -20950 and the suite halves. Check GET /token-status first.',
      'A transport error (ORA-29273 et al) is an unknown outcome, not a failure - MFCS may have acted. Proven live: a PO was created behind one.',
      'The tenant refuses writes during its nightly batch with a plain HTTP 400 ("Batch Running Indicator is ON") - classified -20951, retry later, do not debug.',
    ],
  },
  {
    id: 'mfcs',
    title: 'MFCS tenant',
    pkg: null,
    blurb: 'The real dev tenant. No simulators, no mock mode - by design',
    detail:
      'Every call goes to the live MFCS dev tenant. The project’s hardest-won lesson: an HTTP 200 ' +
      'SUCCESS is not evidence that anything happened. MFCS accepts a diff change on an existing ' +
      'SKU, reports SUCCESS, and ignores it; it did the same for a purchase-order line replacement. ' +
      'Writes are verified by reading back, never by trusting the response.',
    gotchas: [
      'List endpoints are publish/delta feeds, not queries: approved + published records only, a few seconds behind. Empty does not mean absent.',
      'foundation/item/{item} 404s on a style created minutes ago; RmsReSTServices itemDetail returns it in full (and uses a third field vocabulary).',
      'Unknown query parameters are silently ignored - a wrong filter name returns an unfiltered feed that looks filtered.',
    ],
  },
  {
    id: 'respond',
    title: 'Status document returned',
    pkg: 'request_pkg',
    blurb: 'COMPLETED · PARTIALLY_COMPLETED · FAILED_NO_SIDE_EFFECT · OUTCOME_UNKNOWN',
    detail:
      'request_pkg.build_status_response assembles the canonical answer: overall status, the steps ' +
      'that completed, the one that failed, every identifier MFCS generated (style, SKUs, order ' +
      'number), and the errors. The same document is stored so a duplicate submission replays it. ' +
      'PARTIALLY_COMPLETED means real side effects exist and resume can continue; ' +
      'FAILED_NO_SIDE_EFFECT means nothing reached MFCS and a corrected fresh request is safe.',
    gotchas: [],
  },
];

// ---------------------------------------------------------------------------
// Step catalogue: everything the step flows reference, keyed by step code.
// ---------------------------------------------------------------------------
export const STEPS = {
  VALIDATE_REQUEST: {
    title: 'Validate request',
    kind: 'local',
    handler: 'validation_pkg.validate_request',
    detail:
      'Re-marked SUCCEEDED at the top of every execution. Validation actually ran before ' +
      'registration - a document that fails it is rejected with zero side effects and never gets a ' +
      'step graph at all.',
    gotchas: [],
  },
  ENSURE_STYLE_SKUS: {
    title: 'Ensure style SKUs',
    kind: 'subflow',
    handler: 'orchestrator_pkg.ensure_style_skus → sku_pkg + payload_pkg',
    detail:
      'The one genuinely conditional step, and it conditions on the tenant, not on this database. ' +
      'It reads the style’s real children through itemDetail, compares them against the requested ' +
      'colour and size curve, and creates whatever is missing - because a colour change cannot be ' +
      'applied to an existing SKU. In the RMS model a diff combination defines the item, so a new ' +
      'colour means new children; MFCS answers an in-place diff change with SUCCESS and ignores ' +
      'it. See the SKU generation section for the internal flow.',
    gotchas: [
      'Makes up to n+4 MFCS calls inline rather than through the step table - which calls it makes depends on what the tenant already holds.',
      'Re-entrant for free: a resume re-reads the style and creates only what is still absent. A stored payload would replay burned item numbers.',
      'FEATURE_GENERATE_MISSING_SKUS_YN=N restores stop-and-name behaviour: the request fails listing the missing combinations.',
    ],
  },
  RESERVE_ITEM_NUMBERS: {
    title: 'Reserve item numbers',
    kind: 'call',
    handler: 'orchestrator_pkg.reserve_item_numbers_chunked → client_pkg',
    mapper: 'build_item_number_request',
    create: { method: 'POST', endpoint: '/MerchIntegrations/services/item/itemNumbers/reserve' },
    payload: '{"itemNumberType":"ITEM","quantity":1,"daysUntilExpiry":1}',
    detail:
      'One reservation call per item (style + each child), so each number is journalled the moment ' +
      'MFCS hands it over. Numbers land in ENTITY_MAP keyed by the source references - later ' +
      'requests naming the same source style resolve the same MFCS identifiers.',
    gotchas: [
      'Reserved numbers expire (daysUntilExpiry). A request that reserves and then fails permanently burns them - harmless, but visible.',
    ],
  },
  CREATE_PARENT_ITEM_HIERARCHY: {
    title: 'Create parent item',
    kind: 'call',
    handler: 'payload_pkg.parent_item_create_request → client_pkg',
    mapper: 'build_parent_item_create_request',
    create: { method: 'POST', endpoint: '/MerchIntegrations/services/items/create' },
    payload:
      '{"items":[{"item":"100050355","itemLevel":1,"tranLevel":2,\n' +
      '  "diff1":"RMS_ALL_C","diff1Type":"C","diff2":"ALL","diff2Type":"S",\n' +
      '  "dept":1517,"class":6892,"subclass":1128,"status":"W", ...}]}',
    detail:
      'The style itself, at itemLevel 1. Parents carry differentiator GROUPS (RMS_ALL_C / ALL); ' +
      'their children carry concrete diff ids. Created in worksheet status (W) - approval is its ' +
      'own step, after sourcing exists.',
    gotchas: ['Parent styles carry diff groups; children carry concrete diff IDs. Mixing these up is rejected.'],
  },
  CREATE_CHILD_ITEM_HIERARCHY: {
    title: 'Create child items (SKUs)',
    kind: 'call',
    handler: 'payload_pkg.child_item_create_request → client_pkg',
    mapper: 'build_child_item_create_request',
    create: { method: 'POST', endpoint: '/MerchIntegrations/services/items/create' },
    payload:
      '{"items":[{"item":"100050363","itemParent":"100050355","itemLevel":2,\n' +
      '  "diff1":"08610","diff1Type":"C","diff2":"070","diff2Type":"S", ...}]}',
    detail:
      'One child per size-curve row, each carrying the concrete colour diff (diff1) and size diff ' +
      '(diff2) translated through MAP.COLOUR.* and MAP.SIZE.*. The diff pair IS the item’s ' +
      'identity - which is why a colour change later means new children, not an update.',
    gotchas: [],
  },
  CREATE_ITEM_HIERARCHY: {
    title: 'Update items (style + SKUs)',
    kind: 'call',
    handler: 'payload_pkg.item_create_request → client_pkg',
    mapper: 'build_item_create_request',
    create: { method: 'POST', endpoint: '/MerchIntegrations/services/items/create' },
    update: { method: 'PUT', endpoint: '/MerchIntegrations/services/items/update' },
    payload:
      '{"items":[{"item":"100050355","itemDescription":"...","shortDescription":"...",\n' +
      '  "storeOrderMultiple":"E","dataLoadingDestination":"RMS"}, ...]}',
    detail:
      'On operations against an existing style this resolves to items/update and sends the ' +
      'parent plus every child. Update payloads carry only what is being set - but the update ' +
      'service still demands storeOrderMultiple even for a description-only change (proven live: ' +
      '"Field must be entered. Field: STORE_ORD_MULT").',
    gotchas: [
      'The update services want the whole record, not a patch - they refuse on missing columns the create services default.',
      'A diff (colour/size) change sent here returns SUCCESS and is silently ignored. That is why ENSURE_STYLE_SKUS runs first.',
    ],
  },
  CREATE_PARENT_ITEM_SOURCING: {
    title: 'Create parent sourcing',
    kind: 'call',
    handler: 'payload_pkg.parent_item_sourcing_request → client_pkg',
    mapper: 'build_parent_item_sourcing_request',
    create: { method: 'POST', endpoint: '/MerchIntegrations/services/item/suppliers/create' },
    detail: 'Supplier, origin country and unit cost for the parent style. Same shape as the child sourcing step.',
    gotchas: [],
  },
  CREATE_ITEM_SOURCING: {
    title: 'Item sourcing (supplier / cost / country)',
    kind: 'call',
    handler: 'payload_pkg.item_sourcing_request → supplier_payload → client_pkg',
    mapper: 'build_item_sourcing_request',
    create: { method: 'POST', endpoint: '/MerchIntegrations/services/item/suppliers/create' },
    update: { method: 'PUT', endpoint: '/MerchIntegrations/services/item/suppliers/update' },
    payload:
      '{"items":[{"item":"100050363","supplier":[{"supplier":700087,\n' +
      '  "primarySupplierInd":"Y","directShipInd":"N",\n' +
      '  "innerName":"EA","caseName":"CS","palletName":"PAL",\n' +
      '  "countryOfSourcing":[{"originCountry":"GB","unitCost":48.49, ...}]}]}]}',
    detail:
      'Supplier, cost and origin country per item. Approval is impossible without this, which ' +
      'fixes the step order. The packaging names (innerName / caseName / palletName) and ' +
      'directShipInd are sent on both create and update paths: the update service refuses without ' +
      'them, one missing column at a time. Valid values come from the tenant’s own code types ' +
      '(INRN, CASN, PALN) in master data.',
    gotchas: [
      'suppliers/update revealed its required columns one 400 at a time: DIRECT_SHIP_IND, then INNER_NAME. All are sent up front now.',
    ],
  },
  CREATE_ITEM_COUNTRIES_OF_MANUFACTURE: {
    title: 'Countries of manufacture',
    kind: 'call',
    handler: 'payload_pkg.item_country_of_manufacture_request → client_pkg',
    mapper: 'build_item_country_of_manufacture_request',
    create: { method: 'POST', endpoint: '/MerchIntegrations/services/item/supplier/countriesOfManufacture/create' },
    update: { method: 'PUT', endpoint: '/MerchIntegrations/services/item/supplier/countriesOfManufacture/update' },
    payload:
      '{"items":[{"item":"100050363","supplier":[{"supplier":700087,\n' +
      '  "countryOfManufacture":[{"manufacturerCountry":"VN","primaryManufacturerCountryInd":"Y"}]}]}]}',
    detail:
      'Required before approval, alongside sourcing. On an existing style this resolves to the ' +
      'update service, because re-creating an existing row is not a no-op - it is an error: "This ' +
      'item/supplier/manufacturing country already exists" (CORESVC_ITEM.PROCESS_ISMC, proven live).',
    gotchas: ['create cannot be replayed on an existing row - unlike most MFCS writes, this one fails loudly instead of silently succeeding.'],
  },
  CREATE_ITEM_UDAS: {
    title: 'Item UDAs',
    kind: 'call',
    handler: 'payload_pkg.item_uda_request → client_pkg',
    mapper: 'build_item_uda_request',
    create: { method: 'POST', endpoint: '/MerchIntegrations/services/item/uda/create' },
    update: { method: 'PUT', endpoint: '/MerchIntegrations/services/item/uda/update' },
    payload: '{"items":[{"item":"100050363","uda":[]}]}',
    detail:
      'Sends an empty UDA array, which succeeds trivially. Not our bug: this tenant has no UDA ' +
      'definitions - foundation/uda returns zero rows and itemUda is null on every item. The step ' +
      'stays in the graph so the day the tenant gains UDA definitions, the pipe already exists.',
    gotchas: ['Do not "fix" UDAs in code. The tenant side is empty; there is nothing to send until it is not.'],
  },
  CREATE_ITEM_LOCATIONS: {
    title: 'Item locations (ranging)',
    kind: 'call',
    handler: 'payload_pkg.item_location_request → client_pkg',
    mapper: 'build_item_location_request',
    create: { method: 'POST', endpoint: '/MerchIntegrations/services/item/locations/create' },
    update: { method: 'PUT', endpoint: '/MerchIntegrations/services/item/locations/update' },
    payload: '{"items":[{"item":"100050363","location":[{"hierarchyValue":"19271", ...}]}]}',
    detail:
      'Ranges each item to the virtual warehouse. The document’s DELIVERY_LOC is the physical ' +
      'location (1927); MFCS wants the virtual warehouse (19271). Both this mapper and the order ' +
      'mapper translate through MAP.ORDER_LOCATION.* so they cannot disagree. Feature-flagged ' +
      '(FEATURE_ITEM_LOCATIONS_YN) because a purchase order ranges its own items - this step only ' +
      'matters for style-only creates.',
    gotchas: ['Virtual warehouse 19271, not physical 1927. The physical value is silently wrong, not rejected.'],
  },
  APPROVE_ITEMS: {
    title: 'Approve items',
    kind: 'call',
    handler: 'payload_pkg.item_approval_request → client_pkg',
    mapper: 'build_item_approval_request',
    create: { method: 'PUT', endpoint: '/MerchIntegrations/services/items/update' },
    update: { method: 'PUT', endpoint: '/MerchIntegrations/services/items/update' },
    payload: '{"items":[{"item":"100050355","status":"A","approveInd":"Y","storeOrderMultiple":"E", ...}]}',
    detail:
      'Flips parent and children to Approved via items/update. Requires sourcing and country of ' +
      'manufacture to exist first - MFCS refuses otherwise, which is what pins this step last in ' +
      'the item sequence. The parent is always included: a child cannot be approved under an ' +
      'unapproved parent, and re-approving an approved one is free.',
    gotchas: [],
  },
  APPLY_INITIAL_RETAIL: {
    title: 'Apply initial retail',
    kind: 'call',
    handler: 'payload_pkg.initial_retail_request',
    mapper: 'build_initial_retail_request',
    create: { method: 'POST', endpoint: 'ENDPOINT.INITIAL_RETAIL (placeholder)' },
    detail:
      'Feature-flagged off (FEATURE_INITIAL_RETAIL_YN=N) and the endpoint is a placeholder - no ' +
      'matching write service exists in the tenant spec. In the graph so the wiring exists if the ' +
      'tenant ever grows one.',
    gotchas: [],
  },
  RESERVE_ORDER_NUMBER: {
    title: 'Reserve order number',
    kind: 'call',
    handler: 'payload_pkg.po_number_request → client_pkg',
    mapper: 'build_po_number_request',
    create: { method: 'POST', endpoint: '/MerchIntegrations/services/purchaseOrder/preIssuedOrderNumber/create' },
    payload: '{"supplier":700087,"quantity":1,"expiryDays":1}',
    detail:
      'A pre-issued order number from MFCS, persisted to ENTITY_MAP immediately. MODIFY_ORDER ' +
      'skips this step - the order number comes in on the document.',
    gotchas: [],
  },
  CREATE_PURCHASE_ORDER: {
    title: 'Create / update purchase order',
    kind: 'call',
    handler: 'payload_pkg.purchase_order_request → client_pkg',
    mapper: 'build_purchase_order_request',
    create: { method: 'POST', endpoint: '/MerchIntegrations/services/purchaseOrders/create' },
    update: { method: 'PUT', endpoint: '/MerchIntegrations/services/purchaseOrders/update' },
    payload:
      '{"items":[{"orderNo":25012,"supplier":700087,"currencyCode":"ZAR",\n' +
      '  "otbEowDate":"2026-08-23","location":19271,"locationType":"W",\n' +
      '  "details":[{"item":"100050363","quantityOrdered":2,"unitCost":48.49, ...}],\n' +
      '  "expenses":[{"component":"FREIGHT", ...}]}]}',
    detail:
      'The order header, one detail line per SKU (quantities from the size curve), and any ' +
      'non-merchandise costs as expenses. SKUs resolve through ENTITY_MAP, populated either by ' +
      'this request’s earlier steps or recorded by ENSURE_STYLE_SKUS from the tenant. Location is ' +
      'the virtual warehouse via MAP.ORDER_LOCATION.*.',
    gotchas: [
      'purchaseOrders/update is header-only in practice: SUCCESS while the details array is ignored, even for a quantity change on the order’s own lines (proven live). Lines change through the purchaseOrder/details services - which is what the SYNC_ORDER_LINES step exists for.',
      'OTB_EOW_DATE must be a Sunday; MFCS only enforces it here, which is why validation catches it up front.',
    ],
  },
  SYNC_ORDER_LINES: {
    title: 'Sync order lines',
    kind: 'subflow',
    handler: 'orchestrator_pkg.sync_order_lines → payload_pkg.order_details_*',
    detail:
      'Reads the order, then brings its lines to what the document says: details/update for lines ' +
      'it has, details/create for lines it lacks, and this style’s no-longer-named lines cancelled ' +
      'with quantityOrdered:0 + cancelInd + cancelCode. Exists because purchaseOrders/update ' +
      'ignores its details array on this tenant. Verifies by read-back — every named line at its ' +
      'quantity and every cancelled line at zero — waiting out the ~30s lag. Proven live both ' +
      'directions: quantity change, colour switch with cancellation, and switch-back.',
    gotchas: [
      'quantityCancelled is cumulative-absolute and is never sent — a repeat of the existing cancelled quantity is a silent no-op (cost one half-applied cancel live). quantityOrdered is authoritative.',
      'Cancel reasons are the tenant’s own ORCA codes: S (Colour/Location Switched) for a removed line, B (Buyer Cancelled) on a reduction.',
      'Only the document’s own style’s lines can be cancelled; other styles’ lines on the same order are never touched.',
      'A cancelled line is not dead — a later details/update with a quantity resurrects it.',
    ],
  },
  VERIFY_PURCHASE_ORDER: {
    title: 'Verify purchase order',
    kind: 'call',
    handler: 'client_pkg.call_service (GET, with retry loop)',
    mapper: 'build_purchase_order_verify_request',
    create: { method: 'GET', endpoint: '/MerchIntegrations/services/procurement/order/{orderNo}' },
    update: { method: 'GET', endpoint: '/MerchIntegrations/services/procurement/order/{orderNo}' },
    detail:
      'Reads the order back rather than trusting the write’s SUCCESS. The read side lags a few ' +
      'behind - about 30 seconds for line changes, not the few seconds elsewhere - so this retries up ' +
      'to 12 times with 10s sleeps. Currently verifies ' +
      'existence only - the silent no-op on order lines showed it should also compare content ' +
      'against what was sent. That upgrade is on the outstanding list.',
    gotchas: ['Verify-by-readback is the project’s core defence; this step is where it is weakest today (existence, not content).'],
  },
};

// ---------------------------------------------------------------------------
// The five operations and their step sequences (mirrors step_pkg).
// mode: 'create' steps resolve to create endpoints, 'update' to update ones.
// ---------------------------------------------------------------------------
export const OPERATIONS = [
  {
    id: 'CREATE_STYLE',
    label: 'Create style',
    mode: 'create',
    blurb: 'A new style with its SKU children, approved and (optionally) ranged. No order.',
    proven: 'Proven end to end against the tenant.',
    steps: [
      { seq: 10, code: 'VALIDATE_REQUEST' },
      { seq: 20, code: 'RESERVE_ITEM_NUMBERS' },
      { seq: 30, code: 'CREATE_PARENT_ITEM_HIERARCHY' },
      { seq: 35, code: 'CREATE_PARENT_ITEM_SOURCING' },
      { seq: 40, code: 'CREATE_CHILD_ITEM_HIERARCHY' },
      { seq: 50, code: 'CREATE_ITEM_SOURCING' },
      { seq: 55, code: 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE' },
      { seq: 60, code: 'CREATE_ITEM_UDAS' },
      { seq: 70, code: 'CREATE_ITEM_LOCATIONS', flag: 'FEATURE_ITEM_LOCATIONS_YN' },
      { seq: 80, code: 'APPROVE_ITEMS' },
    ],
  },
  {
    id: 'CREATE_ALL',
    label: 'Create style + order',
    mode: 'create',
    blurb: 'The full journey: style, children, approval, then a purchase order against them.',
    proven: 'Proven end to end against the tenant.',
    steps: [
      { seq: 10, code: 'VALIDATE_REQUEST' },
      { seq: 20, code: 'RESERVE_ITEM_NUMBERS' },
      { seq: 30, code: 'CREATE_PARENT_ITEM_HIERARCHY' },
      { seq: 35, code: 'CREATE_PARENT_ITEM_SOURCING' },
      { seq: 40, code: 'CREATE_CHILD_ITEM_HIERARCHY' },
      { seq: 50, code: 'CREATE_ITEM_SOURCING' },
      { seq: 55, code: 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE' },
      { seq: 60, code: 'CREATE_ITEM_UDAS' },
      { seq: 70, code: 'CREATE_ITEM_LOCATIONS', flag: 'FEATURE_ITEM_LOCATIONS_YN' },
      { seq: 80, code: 'APPROVE_ITEMS' },
      { seq: 90, code: 'RESERVE_ORDER_NUMBER' },
      { seq: 100, code: 'CREATE_PURCHASE_ORDER' },
      { seq: 110, code: 'VERIFY_PURCHASE_ORDER' },
    ],
  },
  {
    id: 'MODIFY_STYLE',
    label: 'Modify style',
    mode: 'update',
    blurb:
      'The whole style write set against an existing style - never a diff. Missing colour/size ' +
      'combinations become new children first.',
    proven: 'Completed live 2026-08-22, all seven steps.',
    steps: [
      { seq: 10, code: 'VALIDATE_REQUEST' },
      { seq: 25, code: 'ENSURE_STYLE_SKUS' },
      { seq: 30, code: 'CREATE_ITEM_HIERARCHY' },
      { seq: 40, code: 'CREATE_ITEM_SOURCING' },
      { seq: 45, code: 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE' },
      { seq: 50, code: 'CREATE_ITEM_UDAS' },
      { seq: 60, code: 'CREATE_ITEM_LOCATIONS', flag: 'FEATURE_ITEM_LOCATIONS_YN' },
      { seq: 70, code: 'APPROVE_ITEMS' },
    ],
  },
  {
    id: 'CREATE_ORDER',
    label: 'Create order',
    mode: 'update',
    blurb:
      'An order against an existing style. The style write set runs first - ordering is a ' +
      'statement about the style, not only about the order - then the order is placed on top.',
    proven: 'Completed live 2026-08-22, all eleven steps; order 25012 created and verified.',
    steps: [
      { seq: 10, code: 'VALIDATE_REQUEST' },
      { seq: 25, code: 'ENSURE_STYLE_SKUS' },
      { seq: 30, code: 'CREATE_ITEM_HIERARCHY' },
      { seq: 40, code: 'CREATE_ITEM_SOURCING' },
      { seq: 45, code: 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE' },
      { seq: 50, code: 'CREATE_ITEM_UDAS' },
      { seq: 60, code: 'CREATE_ITEM_LOCATIONS', flag: 'FEATURE_ITEM_LOCATIONS_YN' },
      { seq: 70, code: 'APPROVE_ITEMS' },
      { seq: 90, code: 'RESERVE_ORDER_NUMBER' },
      { seq: 100, code: 'CREATE_PURCHASE_ORDER' },
      { seq: 110, code: 'VERIFY_PURCHASE_ORDER' },
    ],
  },
  {
    id: 'MODIFY_ORDER',
    label: 'Modify order',
    mode: 'update',
    blurb:
      'Same as Create order minus the number reservation - the order number comes in on the document.',
    proven:
      'Proven live 2026-08-22, both directions: quantity change, a full colour switch (new lines ' +
      'created, old ones cancelled with code S), and the switch back - every change verified by ' +
      'reading the order until it matched the document.',
    steps: [
      { seq: 10, code: 'VALIDATE_REQUEST' },
      { seq: 25, code: 'ENSURE_STYLE_SKUS' },
      { seq: 30, code: 'CREATE_ITEM_HIERARCHY' },
      { seq: 40, code: 'CREATE_ITEM_SOURCING' },
      { seq: 45, code: 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE' },
      { seq: 50, code: 'CREATE_ITEM_UDAS' },
      { seq: 60, code: 'CREATE_ITEM_LOCATIONS', flag: 'FEATURE_ITEM_LOCATIONS_YN' },
      { seq: 70, code: 'APPROVE_ITEMS' },
      { seq: 100, code: 'CREATE_PURCHASE_ORDER' },
      { seq: 105, code: 'SYNC_ORDER_LINES' },
      { seq: 110, code: 'VERIFY_PURCHASE_ORDER' },
    ],
  },
];

// ---------------------------------------------------------------------------
// Inside ENSURE_STYLE_SKUS: the colour / missing-SKU logic.
// ---------------------------------------------------------------------------
export const SKU_FLOW = [
  {
    id: 'read',
    title: 'Read the style’s real children',
    tag: 'sku_pkg.existing_skus',
    kind: 'call',
    method: 'GET',
    endpoint: '/RmsReSTServices/services/private/Item/itemDetail?item={style}',
    detail:
      'itemDetail returns a style with all its children in one call - it is not in the OpenAPI ' +
      'spec, and it is the only reliable read for a freshly created style (the foundation/item ' +
      'feed 404s on records created minutes ago). Each child carries its concrete diff pair.',
  },
  {
    id: 'gap',
    title: 'Compare against the requested colour × size curve',
    tag: 'sku_pkg.resolve_gap',
    kind: 'local',
    detail:
      'The document’s colour and each size map through MAP.COLOUR.* / MAP.SIZE.* - the same ' +
      'translations the payload mappers use, so the comparison and the outbound payloads cannot ' +
      'disagree. A SKU matches only when BOTH diffs match: same colour in a new size is a ' +
      'different SKU, and so is the reverse.',
  },
  {
    id: 'decide',
    title: 'All combinations exist?',
    kind: 'decision',
    yes: 'Record each SKU in ENTITY_MAP, step succeeds, request continues',
    no: 'Create the missing children (below), or stop naming them if generation is off',
    detail:
      'The mapping is recorded either way: entity_map is this database’s memory, not the ' +
      'tenant’s, and a style created by an earlier install or by someone else has no rows here ' +
      'until this step files them.',
  },
  {
    id: 'attrs',
    title: 'Read the parent’s attributes',
    tag: 'sku_pkg.style_attributes',
    kind: 'call',
    method: 'GET',
    endpoint: 'itemDetail → typed t_child_plan',
    detail:
      'A child must join its parent’s merchandise hierarchy, and inherits description, retail, ' +
      'supplier, cost and origin country as fallbacks. Everything structural comes from the ' +
      'parent as the tenant holds it - a child that agreed with our config defaults instead of ' +
      'with its parent would be accepted and wrong. The JSON becomes a typed plan record here; ' +
      'from this point a misspelled attribute is a compile error.',
  },
  {
    id: 'reserve',
    title: 'Reserve a number per missing child',
    kind: 'call',
    method: 'POST',
    endpoint: '/MerchIntegrations/services/item/itemNumbers/reserve',
    detail: 'One call per child, each journalled with its diff pair the moment MFCS answers.',
  },
  {
    id: 'create',
    title: 'Create children → sourcing → country of manufacture → approve',
    tag: 'payload_pkg.generated_child_*',
    kind: 'call',
    method: 'POST ×3 + PUT',
    endpoint: 'items/create · suppliers/create · countriesOfManufacture/create · items/update',
    detail:
      'The order is not negotiable: MFCS will not approve an item without sourcing, and will not ' +
      'accept sourcing for an item that does not exist. Only the missing subset is sent - ' +
      're-sending existing combinations would do nothing or make duplicate children.',
  },
  {
    id: 'verify',
    title: 'Read back and verify (retry loop)',
    tag: 'sku_pkg.resolve_gap again',
    kind: 'call',
    method: 'GET',
    endpoint: 'itemDetail, up to 6 × 5s',
    detail:
      'Four HTTP 200s prove nothing - MFCS answers a no-op write with SUCCESS. The only evidence ' +
      'the children exist is finding them, so the style is re-read until every requested ' +
      'combination is present. Newly approved items take a moment to become readable, hence the ' +
      'retries. If the combinations never appear, the step fails naming what MFCS swallowed.',
  },
];

// ---------------------------------------------------------------------------
// Failure classification and resume.
// ---------------------------------------------------------------------------
export const FAILURE_FLOW = {
  classes: [
    {
      code: '-20950',
      name: 'MFCS rejected the call',
      colour: 'red',
      detail:
        'HTTP 4xx/5xx with a readable body. The step is FAILED, the response is journalled in ' +
        'ATTEMPT, and the request lands PARTIALLY_COMPLETED (something already succeeded) or ' +
        'FAILED_NO_SIDE_EFFECT (nothing did). The error body usually names the exact column - ' +
        'read it in the Activity tab before touching code.',
    },
    {
      code: '-20951',
      name: 'MFCS unavailable',
      colour: 'amber',
      detail:
        'HTTP 503, or the tenant’s nightly batch window ("Batch Running Indicator is ON" - a ' +
        'plain 400 that would otherwise read as a payload bug). Nothing to fix: wait and resume.',
    },
    {
      code: '-20952',
      name: 'Outcome unknown',
      colour: 'accent',
      detail:
        'The transport failed after the request may have been sent (ORA-29273/29276/29259, TNS ' +
        'timeouts). Classified by SQLCODE, never by message text - ORA-29273 once hid a purchase ' +
        'order that had actually been created. The attempt is marked OUTCOME_UNKNOWN and resolution ' +
        'is deferred to recovery.',
    },
  ],
  recovery: [
    {
      id: 'r1',
      title: 'Resume re-enters the same loop',
      detail:
        'resume_request IS execute_request: the loop picks up at the first step not yet SUCCEEDED. ' +
        'Succeeded steps are skipped; FAILED and OUTCOME_UNKNOWN steps are runnable again. There is ' +
        'no separate resume path to drift from the main one.',
    },
    {
      id: 'r2',
      title: 'OUTCOME_UNKNOWN resolves by correlation id',
      detail:
        'recovery_pkg asks MFCS’s operation-status service what happened to the correlation id the ' +
        'attempt journalled. SUCCESS → step marked done and skipped. FAILURE → step failed, runs ' +
        'again. NO_RECORD → the call never landed; the step simply re-runs. Still ambiguous → the ' +
        'request parks as MANUAL_REVIEW rather than guessing.',
    },
    {
      id: 'r3',
      title: 'Resume replays the STORED payload',
      detail:
        'A request that failed because of a bad value in its document cannot be rescued by ' +
        'resuming - the same payload replays. Fix the value and submit a fresh request. The one ' +
        'exception is ENSURE_STYLE_SKUS, which stores no payload: it re-reads the tenant on every ' +
        'entry and does only what is still needed.',
    },
  ],
};

// ---------------------------------------------------------------------------
// Package quick reference.
// ---------------------------------------------------------------------------
export const PACKAGES = [
  { n: '01', name: 'config_pkg', role: 'CONFIG lookups: endpoints, defaults, MAP.* translations, feature flags. Values are data; structure is code.' },
  { n: '02', name: 'event_pkg', role: 'Autonomous event log - survives the rollback of the step that logged it. Also owns the one JSON escape helper.' },
  { n: '03', name: 'request_pkg', role: 'Registration, idempotency (NEW / DUPLICATE / CONFLICT), status document, ENTITY_MAP identifiers.' },
  { n: '04', name: 'step_pkg', role: 'Writes the full step plan up front; journals every outbound call as an ATTEMPT with a correlation id.' },
  { n: '05', name: 'validation_pkg', role: 'Rejects bad documents before any side effect, reporting every problem at once.' },
  { n: '06', name: 'payload_pkg', role: 'The whole MFCS write contract: every request body, one mapper per shape, statically wired. Owns c_size_curve and t_child_plan.' },
  { n: '07', name: 'client_pkg', role: 'The only outbound HTTP path and the only credential reader. Classifies failures: rejected / unavailable / unknown.' },
  { n: '08', name: 'recovery_pkg', role: 'Resolves OUTCOME_UNKNOWN attempts by asking MFCS what happened to the correlation id.' },
  { n: '09', name: 'orchestrator_pkg', role: 'The execution loop, resolve_step (endpoint + method + mapper in one record), and the ENSURE_STYLE_SKUS sub-flow.' },
  { n: '10', name: 'preview_pkg', role: 'Builds the full call plan without sending anything, through the orchestrator’s own resolver - a preview cannot drift from execution.' },
  { n: '11', name: 'master_pkg', role: 'Foundation-data cache. Most foundation services are empty publish queues, so much is derived from the item/order feeds; every row records its SOURCE.' },
  { n: '12', name: 'browse_pkg', role: 'Live style and order reads for the console, uncached on purpose. Children via itemDetail with a feed-scan fallback.' },
  { n: '14', name: 'sku_pkg', role: 'Read-only SKU analysis: what a style has (existing_skus), what a request needs (resolve_gap), what a child inherits (style_attributes).' },
  { n: '15', name: 'api_pkg', role: 'Public entry points behind ORDS: submit, validate, get, resume. Owns the error-code registry comment.' },
  { n: '16', name: 'ords_util_pkg', role: 'Chunked response output - htp.prn is VARCHAR2-bound and item feeds cross 32KB after ~7 rows.' },
];
