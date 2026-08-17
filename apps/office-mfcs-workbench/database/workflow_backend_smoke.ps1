$ErrorActionPreference = 'Stop'
$baseUrl = 'https://127.0.0.1:8443/ords/office_mfcs_ui_app/office-workflow/v1'

function Invoke-WorkflowApi {
    param([string] $Method, [string] $Path, [object] $Body, [int] $ExpectedStatus = 200)
    $json = if ($null -eq $Body) { '' } elseif ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 30 -Compress }
    $args = @('exec', '-i', 'adb-free', 'curl', '-k', '-sS', '--max-time', '20', '-X', $Method, '-H', 'Content-Type: application/json', '--data-binary', '@-', '-w', "`nHTTP_STATUS:%{http_code}", "$baseUrl/$Path")
    $raw = $json | & docker @args
    if ($LASTEXITCODE -ne 0) { throw "Workflow request failed: $Method $Path" }
    $parts = (($raw -join "`n") -split 'HTTP_STATUS:')
    $status = [int]$parts[1].Trim()
    $text = $parts[0].Trim()
    if ($status -ne $ExpectedStatus) { throw "Expected HTTP $ExpectedStatus, got $status for $Method $Path. Body=$text" }
    if ($text) { return $text | ConvertFrom-Json }
}

function Assert-Equal($Actual, $Expected, [string] $Message) {
    if ($Actual -ne $Expected) { throw "$Message. Expected=$Expected Actual=$Actual" }
}

$requestId = [guid]::NewGuid().ToString()
$actionId = [guid]::NewGuid().ToString()
$now = [DateTime]::UtcNow.ToString('o')
$buyer = @{ id = 'jane.buyer@office.example'; name = 'Jane Buyer'; role = 'BUYER' }
$manager = @{ id = 'michael.manager@office.example'; name = 'Michael Manager'; role = 'MANAGER' }
$request = @{
    id = $requestId; officeReference = "SMOKE-$($requestId.Substring(0,8).ToUpper())"; operationName = 'CREATE_ALL'
    sourceStyleRef = "SMOKE-STYLE-$requestId"; sourceOrderRef = "SMOKE-ORDER-$requestId"; sourceVersion = 1
    status = 'DRAFT'; createdBy = $buyer; createdAt = $now; updatedAt = $now; approvalHistory = @()
    style = @{ existingStyle = ''; description = 'Oracle Workflow Smoke Trainer'; shortDescription = 'Smoke Trainer'; department = 100; classNumber = 10; subclass = 1; colourGroup = 'OFFICE_COLOUR'; colour = 'BLACK'; sizeGroup = 'SHOE_SIZE'; widthGroup = 'WIDTH_STD'; season = 'AW26'; phase = '1' }
    sourcing = @{ supplier = 70001; vpn = 'SMOKE-VPN'; originCountry = 'CN'; manufacturingCountry = 'CN'; currencyCode = 'USD'; costPrice = 22.75; nonMerchCost = 1.2; rsp = 69.99; casePackSize = 1; innerPackSize = 1 }
    variants = @(@{ id = [guid]::NewGuid().ToString(); sourceVariantRef = "SMOKE-STYLE-$requestId-UK8"; size = '8'; width = 'STANDARD'; quantity = 12; skuId = '' })
    order = @{ existingOrderNo = ''; deliveryLocation = 98; poType = '2'; notBeforeDate = '2026-10-12'; notAfterDate = '2026-10-18'; otbEowDate = '2026-10-18'; earliestShipDate = '2026-08-20'; latestShipDate = '2026-08-30'; exchangeRate = 1; specialInstructions = ''; dutyCode = '6403.99.00'; dutyRate = 0.08 }
    diagnosticPadding = 'x' * 34000
}

$saved = Invoke-WorkflowApi PUT "requests/$requestId" $request 201
Assert-Equal $saved.status 'DRAFT' 'Draft save failed'
$listed = Invoke-WorkflowApi GET 'requests' $null
if (-not ($listed | Where-Object id -eq $requestId)) { throw 'Large request was missing from the workflow list.' }
$submitted = Invoke-WorkflowApi POST "requests/$requestId/submit" $buyer
Assert-Equal $submitted.status 'SUBMITTED' 'Submit transition failed'
$returned = Invoke-WorkflowApi POST "requests/$requestId/return" @{ actor = $manager; reason = 'Confirm the delivery window.' }
Assert-Equal $returned.status 'RETURNED' 'Return transition failed'
$corrected = Invoke-WorkflowApi POST "requests/$requestId/correct" $buyer
Assert-Equal $corrected.status 'DRAFT' 'Correction transition failed'
Assert-Equal $corrected.sourceVersion 2 'Correction did not increment source version'
$corrected.PSObject.Properties.Remove('diagnosticPadding')
$corrected.style.description = 'Oracle Workflow Smoke Trainer Corrected'
$corrected.updatedAt = [DateTime]::UtcNow.ToString('o')
$null = Invoke-WorkflowApi PUT "requests/$requestId" $corrected
$resubmitted = Invoke-WorkflowApi POST "requests/$requestId/submit" $buyer
Assert-Equal $resubmitted.status 'SUBMITTED' 'Resubmit transition failed'

$payload = @{
    OPERATION_NAME = 'CREATE_ALL'; ACTION_REQUEST_ID = $actionId; SOURCE_SYSTEM = 'OFFICE_ORDERING'
    SOURCE_STYLE_REF = $request.sourceStyleRef; SOURCE_ORDER_REF = $request.sourceOrderRef; SOURCE_VERSION = '2'
    USER_ID = $manager.id; DATE_TIME_STAMP = [DateTime]::UtcNow.ToString('o'); STYLE = $null; ORDER_NO = $null
    DEPARTMENT = 100; CLASS = 10; SUBCLASS = 1; COLOUR_GROUP = 'OFFICE_COLOUR'; COLOUR = 'BLACK'
    SIZE_GROUP = 'SHOE_SIZE'; WIDTH_GROUP = 'WIDTH_STD'; PACK_IND = 'N'
    STYLE_DESC = $corrected.style.description; STYLE_SHORT_DESC = 'Smoke Trainer'
    SUPPLIER = 70001; VPN = 'SMOKE-VPN'; ORIGIN_COUNTRY = 'CN'; MANUFACTURE_CTRY = 'CN'; CURRENCY_CODE = 'USD'
    COST_PRICE = 22.75; UNIT_COST = 22.75; NON_MERCH_COST = 1.2; UPDATE_COST_IND = 'Y'
    PACK_SIZE_CASE = 1; PACK_SIZE_INNER = 1; RSP = 69.99; RETAIL_PRICE = 69.99; UPDATE_RSP_IND = 'Y'
    SEASON = 'AW26'; PHASE = '1'
    PLMSizeCurveDtl = @(@{ SOURCE_VARIANT_REF = $request.variants[0].sourceVariantRef; SKU_SIZE = '8'; SKU_WIDTH = 'STANDARD'; SKU_QTY = 12; SKU_ID = $null })
    PLMPacklotDtl = $null; PLMStyleUDADtl = @()
    NOT_BEFORE_DATE = '2026-10-12'; NOT_AFTER_DATE = '2026-10-18'; OTB_EOW_DATE = '2026-10-18'
    EARLIEST_SHIP_DATE = '2026-08-20'; LATEST_SHIP_DATE = '2026-08-30'; DELIVERY_LOC = 98
    PO_TYPE = '2'; ORDER_EXCHANGE_RATE = 1; VALLEY_PERIOD_IND = 'N'; ON_HANGER = 'N'; FIRST_PASS = 'N'
    TICKETS_REQUIRED = 'N'; PDF_PO_STATUS = 'N'; SPECIAL_INSTRUCTION = $null; DUTY_CODE = '6403.99.00'; DUTY_RATE = 0.08
}
$posted = Invoke-WorkflowApi POST "requests/$requestId/approve" @{ actor = $manager; payload = $payload }
Assert-Equal $posted.status 'POSTED' 'Live Local MFCS posting did not complete'
Assert-Equal $posted.actionRequestId $actionId 'Approved action request ID changed'
Assert-Equal $posted.integrationResponse.STATUS 'COMPLETED' 'Live integration response is not completed'
if (-not $posted.integrationResponse.STYLE) { throw 'Live integration did not return a style number.' }
if (-not $posted.integrationResponse.ORDER_NO) { throw 'Live integration did not return an order number.' }
$state = Invoke-WorkflowApi GET "state/$($posted.integrationResponse.ORDER_NO)" $null
Assert-Equal $state.foundBy 'ORDER' 'Posted order was not readable from Local MFCS state'
Assert-Equal $state.styles[0].item $posted.integrationResponse.STYLE 'State viewer returned the wrong style'

Write-Output "Live workflow smoke passed: request=$requestId style=$($posted.integrationResponse.STYLE) order=$($posted.integrationResponse.ORDER_NO) assertions=14"
