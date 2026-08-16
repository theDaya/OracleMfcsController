$ErrorActionPreference = 'Stop'

$baseUrl = 'https://127.0.0.1:8443/ords/office_mfcs_app/local-mfcs'
$script:correlationSequence = 0

function Assert-True {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message
    )

    if (-not $Condition) {
        throw "Local MFCS assertion failed: $Message"
    }
}

function Invoke-LocalMfcs {
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,
        [object] $Body,
        [int] $ExpectedStatus = 200,
        [string] $CorrelationId
    )

    if (-not $CorrelationId) {
        $script:correlationSequence++
        $CorrelationId = "local-mfcs-http-$($script:correlationSequence)"
    }

    $json = if ($null -eq $Body) { '' } else { $Body | ConvertTo-Json -Depth 20 -Compress }
    $dockerArgs = @(
        'exec', '-i', 'adb-free',
        'curl', '-k', '-sS', '--max-time', '20',
        '-X', $Method,
        '-H', 'Content-Type: application/json',
        '-H', "X-Correlation-ID: $CorrelationId",
        '--data-binary', '@-',
        '-w', "`nHTTP_STATUS:%{http_code}",
        "$baseUrl/$Path"
    )

    $raw = $json | & docker @dockerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "ORDS request failed to execute: $Method $Path"
    }

    $parts = (($raw -join "`n") -split 'HTTP_STATUS:')
    $status = [int]$parts[1].Trim()
    $responseBody = $parts[0].Trim()
    if ($status -ne $ExpectedStatus) {
        throw "Unexpected HTTP status for $Method $Path. Expected $ExpectedStatus, got $status. Body=$responseBody"
    }

    [pscustomobject]@{
        Status = $status
        Body = $responseBody
        Json = if ($responseBody) { $responseBody | ConvertFrom-Json } else { $null }
        CorrelationId = $CorrelationId
    }
}

Invoke-LocalMfcs -Method POST -Path '__admin/reset' -Body @{} | Out-Null

$health = Invoke-LocalMfcs -Method GET -Path 'health'
Assert-True ($health.Json.status -eq 'UP') 'health endpoint reports UP'

$itemReservation = Invoke-LocalMfcs -Method POST -Path 'MerchIntegrations/services/item/itemNumbers/reserve' -Body @{
    quantity = 2
    daysUntilExpiry = 14
    itemNumberType = 'ITEM'
}
$style = [string]$itemReservation.Json.items[0].item
$sku = [string]$itemReservation.Json.items[1].item
Assert-True ($style -and $sku -and $style -ne $sku) 'two unique item numbers are reserved'

$itemCreate = @{
    collectionSize = 2
    items = @(
        @{
            item = $style
            itemNumberType = 'ITEM'
            itemDescription = 'Local MFCS HTTP Style'
            itemLevel = 1
            tranLevel = 2
            dept = 100
            class = 10
            subclass = 1
            status = 'W'
            standardUom = 'EA'
            merchandiseInd = 'Y'
            inventoryInd = 'Y'
            sellableInd = 'Y'
            orderableInd = 'Y'
            diff1 = 'SHOE_SIZE'
            diff1Type = 'S'
            diff2 = 'WIDTH_STD'
            diff2Type = 'W'
            diff3 = 'COLOR_STD'
            diff3Type = 'C'
            dataLoadingDestination = 'RMS'
        },
        @{
            item = $sku
            itemNumberType = 'ITEM'
            itemParent = $style
            itemDescription = 'Local MFCS HTTP Style 8 Standard'
            itemLevel = 2
            tranLevel = 2
            dept = 100
            class = 10
            subclass = 1
            status = 'W'
            standardUom = 'EA'
            merchandiseInd = 'Y'
            inventoryInd = 'Y'
            sellableInd = 'Y'
            orderableInd = 'Y'
            diff1 = '8'
            diff1Type = 'S'
            diff2 = 'STANDARD'
            diff2Type = 'W'
            diff3 = 'BLACK'
            diff3Type = 'C'
            originalRetail = 49.99
            dataLoadingDestination = 'RMS'
        }
    )
}
Invoke-LocalMfcs -Method POST -Path 'MerchIntegrations/services/items/create' -Body $itemCreate | Out-Null

$sourcing = @{
    collectionSize = 1
    items = @(@{
        item = $sku
        dataLoadingDestination = 'RMS'
        supplier = @(@{
            supplier = 70001
            primarySupplierInd = 'Y'
            countryOfSourcing = @(@{
                originCountry = 'CN'
                primaryCountryInd = 'Y'
                unitCost = 22.75
            })
        })
    })
}
Invoke-LocalMfcs -Method POST -Path 'MerchIntegrations/services/item/suppliers/create' -Body $sourcing | Out-Null

$udas = @{
    collectionSize = 1
    items = @(@{
        item = $sku
        dataLoadingDestination = 'RMS'
        uda = @(@{ udaId = 9001; udaValue = 'HTTP-SMOKE' })
    })
}
Invoke-LocalMfcs -Method POST -Path 'MerchIntegrations/services/item/uda/create' -Body $udas | Out-Null

$locations = @{
    collectionSize = 1
    items = @(@{
        item = $sku
        dataLoadingDestination = 'RMS'
        locations = @(@{ location = 98; locationType = 'S'; status = 'A' })
    })
}
Invoke-LocalMfcs -Method POST -Path 'MerchIntegrations/services/item/locations/create' -Body $locations | Out-Null

$approval = @{
    collectionSize = 2
    items = @(
        @{ item = $style; status = 'A'; approveInd = 'Y'; dataLoadingDestination = 'RMS' },
        @{ item = $sku; status = 'A'; approveInd = 'Y'; dataLoadingDestination = 'RMS' }
    )
}
Invoke-LocalMfcs -Method PUT -Path 'MerchIntegrations/services/items/update' -Body $approval | Out-Null

$itemUpdate = @{
    collectionSize = 1
    items = @(@{
        item = $sku
        itemDescription = 'Local MFCS HTTP Style 8 Updated'
        originalRetail = 54.99
        dataLoadingDestination = 'RMS'
    })
}
Invoke-LocalMfcs -Method PUT -Path 'MerchIntegrations/services/items/update' -Body $itemUpdate | Out-Null

$orderReservation = Invoke-LocalMfcs -Method POST -Path 'MerchIntegrations/services/purchaseOrder/preIssuedOrderNumber/create' -Body @{
    supplier = 70001
    quantity = 1
    expiryDays = 14
}
$orderNo = [long]$orderReservation.Json.orderNumbers[0].orderNo
Assert-True ($orderNo -gt 0) 'an order number is reserved'

$po = @{
    items = @(@{
        orderNo = $orderNo
        supplier = 70001
        currencyCode = 'USD'
        dept = 100
        status = 'A'
        exchangeRate = 1
        notBeforeDate = '2026-08-18'
        notAfterDate = '2026-09-30'
        earliestShipDate = '2026-08-20'
        latestShipDate = '2026-09-15'
        approvedBy = 'local-mfcs-http-smoke'
        dataLoadingDestination = 'RMS'
        details = @(@{
            item = $sku
            location = 98
            locationType = 'S'
            originCountryId = 'CN'
            qtyOrdered = 10
            unitCost = 22.75
        })
    })
}
Invoke-LocalMfcs -Method POST -Path 'MerchIntegrations/services/purchaseOrders/create' -Body $po | Out-Null

$po.items[0].details[0].qtyOrdered = 12
$po.items[0].details[0].unitCost = 23.00
$poUpdateCorrelation = 'local-mfcs-http-po-update'
Invoke-LocalMfcs -Method PUT -Path 'MerchIntegrations/services/purchaseOrders/update' -Body $po -CorrelationId $poUpdateCorrelation | Out-Null

$order = Invoke-LocalMfcs -Method GET -Path "MerchIntegrations/services/procurement/order/$orderNo"
Assert-True ([int]$order.Json.items[0].details[0].qtyOrdered -eq 12) 'PO update is visible through procurement order GET'
Assert-True ([decimal]$order.Json.items[0].totalCost -eq 276) 'PO total cost is recalculated from ORDLOC'

$status = Invoke-LocalMfcs -Method GET -Path "MerchIntegrations/services/administration/operations/restService/status?xCorrelationId=$poUpdateCorrelation"
Assert-True ([int]$status.Json.count -eq 1) 'correlation status returns one matching event'
Assert-True ([int]$status.Json.items[0].responseCode -eq 200) 'correlation status reports HTTP 200'

$state = Invoke-LocalMfcs -Method GET -Path '__admin/state'
Assert-True ([int]$state.Json.tableCounts.ITEM_MASTER -eq 2) 'state contains style and SKU'
Assert-True ([int]$state.Json.tableCounts.ITEM_SUPPLIER -eq 1) 'state contains item supplier sourcing'
Assert-True ([int]$state.Json.tableCounts.ITEM_SUPP_COUNTRY -eq 1) 'state contains supplier country sourcing'
Assert-True ([int]$state.Json.tableCounts.ITEM_LOC -eq 1) 'state contains item location ranging'
Assert-True ([int]$state.Json.tableCounts.ORDHEAD -eq 1) 'state contains one order header'
Assert-True ([int]$state.Json.tableCounts.ORDSKU -eq 1) 'state contains one order SKU'
Assert-True ([int]$state.Json.tableCounts.ORDLOC -eq 1) 'state contains one order location'

$invalid = @{
    collectionSize = 1
    items = @(@{
        item = '3999998'
        itemDescription = 'Invalid Differentiator'
        itemLevel = 1
        tranLevel = 1
        dept = 100
        class = 10
        subclass = 1
        diff1 = 'DOES_NOT_EXIST'
        diff1Type = 'S'
        dataLoadingDestination = 'RMS'
    })
}
$negative = Invoke-LocalMfcs -Method POST -Path 'MerchIntegrations/services/items/create' -Body $invalid -ExpectedStatus 400
Assert-True ($negative.Json.validationErrors[0].field -eq 'items.diff1') 'unknown diff is rejected at the REST boundary'

Write-Output "Local MFCS ORDS smoke passed: style=$style sku=$sku order=$orderNo assertions=14"
