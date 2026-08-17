$ErrorActionPreference = 'Stop'
$simulatorStateUrl = 'https://127.0.0.1:8443/ords/office_mfcs_app/local-mfcs/__admin/state'
$viewerBaseUrl = 'https://127.0.0.1:8443/ords/office_mfcs_ui_app/office-workflow/v1/state'

function Invoke-ContainerJson {
    param([string] $Url, [int] $ExpectedStatus = 200)
    $raw = & docker exec adb-free curl -k -sS --max-time 20 -w "`nHTTP_STATUS:%{http_code}" $Url
    if ($LASTEXITCODE -ne 0) { throw "Request failed: $Url" }
    $parts = (($raw -join "`n") -split 'HTTP_STATUS:')
    $status = [int]$parts[1].Trim()
    $text = $parts[0].Trim()
    if ($status -ne $ExpectedStatus) { throw "Expected HTTP $ExpectedStatus, got $status. Body=$text" }
    return $text | ConvertFrom-Json
}

function Assert-True($Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$snapshot = Invoke-ContainerJson $simulatorStateUrl
$orderNo = $snapshot.orders[0].orderNo
$style = $snapshot.items | Where-Object { $_.itemLevel -eq 1 } | Select-Object -First 1
$sku = $snapshot.items | Where-Object { $_.itemLevel -gt 1 } | Select-Object -First 1
Assert-True ($null -ne $orderNo -and $null -ne $style) 'Simulator must contain at least one order and style.'

$orderResult = Invoke-ContainerJson "$viewerBaseUrl/$orderNo"
Assert-True ($orderResult.foundBy -eq 'ORDER') 'Order lookup did not resolve as ORDER.'
Assert-True ($orderResult.orders[0].orderNo -eq $orderNo) 'Order lookup returned the wrong order.'
Assert-True ($orderResult.items.Count -gt 0) 'Order lookup did not include associated items.'

$styleResult = Invoke-ContainerJson "$viewerBaseUrl/$($style.item)"
Assert-True ($styleResult.foundBy -eq 'STYLE') 'Style lookup did not resolve as STYLE.'
Assert-True ($styleResult.orders[0].orderNo -eq $orderNo) 'Style lookup did not include the related order.'

if ($null -ne $sku) {
    $skuResult = Invoke-ContainerJson "$viewerBaseUrl/$($sku.item)"
    Assert-True ($skuResult.foundBy -eq 'SKU') 'SKU lookup did not resolve as SKU.'
    Assert-True ($skuResult.styles[0].item -eq $style.item) 'SKU lookup did not resolve its parent style.'
}

$notFound = Invoke-ContainerJson "$viewerBaseUrl/99999999" 404
Assert-True ($notFound.message -like 'No MFCS*') 'Not-found lookup did not return the expected message.'

Write-Output "MFCS state viewer smoke passed: order=$orderNo style=$($style.item) assertions=8"
