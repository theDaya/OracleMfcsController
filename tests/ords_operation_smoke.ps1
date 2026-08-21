$ErrorActionPreference = 'Stop'

$basePayload = Get-Content -Raw "$PSScriptRoot\sample_create_all.json" | ConvertFrom-Json
$endpoint = 'https://localhost:8443/ords/mfcs_integration/mfcs/v1/transactions'
$validateEndpoint = "$endpoint/validate"
$operations = @(
    'CREATE_ALL',
    'CREATE_STYLE',
    'CREATE_ORDER',
    'MODIFY_STYLE',
    'MODIFY_ORDER'
)

function Invoke-OrdsJson {
    param(
        [Parameter(Mandatory)] [string] $Json,
        [Parameter(Mandatory)] [string] $Url
    )

    $dockerArgs = @(
        'exec', '-i', 'adb-free',
        'curl', '-k', '-sS', '--max-time', '20',
        '-H', 'Content-Type: application/json',
        '--data-binary', '@-',
        '-w', "`nHTTP_STATUS:%{http_code}",
        $Url
    )

    $rawResponse = $Json | & docker @dockerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "ORDS request failed to execute for $Url."
    }

    $responseText = $rawResponse -join "`n"
    $parts = $responseText -split 'HTTP_STATUS:'
    [pscustomobject]@{
        HttpStatus = [int]$parts[1].Trim()
        Body = $parts[0].Trim()
    }
}

function Copy-BasePayload {
    $basePayload | ConvertTo-Json -Depth 20 | ConvertFrom-Json
}

foreach ($operation in $operations) {
    $payload = Copy-BasePayload
    $suffix = $operation.Replace('_', '-')
    $payload.ACTION_REQUEST_ID = "O-$suffix-20260816"
    $payload.OPERATION_NAME = $operation
    $payload.SOURCE_STYLE_REF = "ORDS-STYLE-$suffix-20260816"
    $payload.SOURCE_ORDER_REF = "ORDS-ORDER-$suffix-20260816"

    foreach ($variant in $payload.PLMSizeCurveDtl) {
        $variant.SOURCE_VARIANT_REF = "$($payload.SOURCE_STYLE_REF)-$($variant.SKU_SIZE)"
    }

    switch ($operation) {
        'CREATE_ALL' {
            $payload.STYLE = $null
            $payload.ORDER_NO = $null
            $payload.PLMSizeCurveDtl | ForEach-Object { $_.SKU_ID = $null }
        }
        'CREATE_STYLE' {
            $payload.STYLE = $null
            $payload.ORDER_NO = $null
            $payload.PLMSizeCurveDtl | ForEach-Object { $_.SKU_ID = $null }
        }
        'CREATE_ORDER' {
            $payload.STYLE = '3500001'
            $payload.ORDER_NO = $null
            $payload.PLMSizeCurveDtl[0].SKU_ID = '10300001'
            $payload.PLMSizeCurveDtl[1].SKU_ID = '10300002'
        }
        'MODIFY_STYLE' {
            $payload.STYLE = '3500001'
            $payload.ORDER_NO = $null
            $payload.PLMSizeCurveDtl[0].SKU_ID = '10300001'
            $payload.PLMSizeCurveDtl[1].SKU_ID = '10300002'
        }
        'MODIFY_ORDER' {
            $payload.STYLE = '3500001'
            $payload.ORDER_NO = '10740001'
            $payload.PLMSizeCurveDtl[0].SKU_ID = '10300001'
            $payload.PLMSizeCurveDtl[1].SKU_ID = '10300002'
        }
    }

    $json = $payload | ConvertTo-Json -Depth 20 -Compress
    $result = Invoke-OrdsJson -Json $json -Url $endpoint
    $response = $result.Body | ConvertFrom-Json

    if ($result.HttpStatus -ne 200 -or $response.STATUS -ne 'COMPLETED') {
        throw "$operation failed: HTTP $($result.HttpStatus) body=$($result.Body)"
    }

    Write-Output "$operation HTTP=$($result.HttpStatus) STATUS=$($response.STATUS) STYLE=$($response.STYLE) ORDER_NO=$($response.ORDER_NO)"
}

Write-Output "ORDS operation smoke tests passed: $($operations.Count)"

$negativeCases = @()

$payload = Copy-BasePayload
$payload.ACTION_REQUEST_ID = 'O-NEG-MISSING-SOURCE-20260816'
$payload.PSObject.Properties.Remove('SOURCE_SYSTEM')
$negativeCases += [pscustomobject]@{ Name = 'missing source system'; Json = ($payload | ConvertTo-Json -Depth 20 -Compress); Url = $validateEndpoint; Http = 422; Code = 'REQUIRED' }

$payload = Copy-BasePayload
$payload.ACTION_REQUEST_ID = 'O-NEG-DUPLICATE-VARIANT-20260816'
$payload.PLMSizeCurveDtl[1].SKU_SIZE = $payload.PLMSizeCurveDtl[0].SKU_SIZE
$negativeCases += [pscustomobject]@{ Name = 'duplicate size/width'; Json = ($payload | ConvertTo-Json -Depth 20 -Compress); Url = $validateEndpoint; Http = 422; Code = 'DUPLICATE_SIZE_WIDTH' }

$payload = Copy-BasePayload
$payload.ACTION_REQUEST_ID = 'O-NEG-ZERO-QTY-20260816'
$payload.PLMSizeCurveDtl[0].SKU_QTY = 0
$negativeCases += [pscustomobject]@{ Name = 'zero quantity'; Json = ($payload | ConvertTo-Json -Depth 20 -Compress); Url = $validateEndpoint; Http = 422; Code = 'POSITIVE_WHOLE_NUMBER_REQUIRED' }

$payload = Copy-BasePayload
$payload.ACTION_REQUEST_ID = 'O-NEG-BAD-DATE-20260816'
$payload.NOT_BEFORE_DATE = 'not-a-date'
$negativeCases += [pscustomobject]@{ Name = 'malformed date'; Json = ($payload | ConvertTo-Json -Depth 20 -Compress); Url = $validateEndpoint; Http = 422; Code = 'INVALID_DATE' }

$payload = Copy-BasePayload
$payload.ACTION_REQUEST_ID = 'O-NEG-NO-DELIVERY-20260816'
$payload.OPERATION_NAME = 'CREATE_ORDER'
$payload.STYLE = '3500001'
$payload.ORDER_NO = $null
$payload.PLMSizeCurveDtl[0].SKU_ID = '10300001'
$payload.PLMSizeCurveDtl[1].SKU_ID = '10300002'
$payload.PSObject.Properties.Remove('DELIVERY_LOC')
$negativeCases += [pscustomobject]@{ Name = 'missing delivery location'; Json = ($payload | ConvertTo-Json -Depth 20 -Compress); Url = $validateEndpoint; Http = 422; Code = 'REQUIRED' }

$payload = Copy-BasePayload
$payload.ACTION_REQUEST_ID = 'O-NEG-NO-OPERATION-20260816'
$payload.PSObject.Properties.Remove('OPERATION_NAME')
$negativeCases += [pscustomobject]@{ Name = 'missing operation'; Json = ($payload | ConvertTo-Json -Depth 20 -Compress); Url = $endpoint; Http = 400; Code = 'REQUIRED' }

$negativeCases += [pscustomobject]@{ Name = 'malformed JSON'; Json = '{"ACTION_REQUEST_ID":'; Url = $endpoint; Http = 400; Code = 'INVALID_JSON' }

foreach ($case in $negativeCases) {
    $result = Invoke-OrdsJson -Json $case.Json -Url $case.Url
    $response = $result.Body | ConvertFrom-Json
    $codes = @($response.ERRORS | ForEach-Object { $_.CODE })

    if ($result.HttpStatus -ne $case.Http -or $codes -notcontains $case.Code) {
        throw "$($case.Name) failed: HTTP $($result.HttpStatus) codes=$($codes -join ',') body=$($result.Body)"
    }

    Write-Output "NEGATIVE $($case.Name) HTTP=$($result.HttpStatus) CODE=$($case.Code)"
}

Write-Output "ORDS negative smoke tests passed: $($negativeCases.Count)"
