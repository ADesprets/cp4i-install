<#
.SYNOPSIS
    Génère des fausses commandes via le générateur Java (faker) et les injecte dans l'API de persistance OrderP.

.DESCRIPTION
    Ce script exécute une boucle pour appeler l'endpoint de génération Java (Datafaker) afin d'obtenir
    des payloads de commandes fictives, puis les injecte unitairement dans l'API REST OrderP (Liberty/PostgreSQL).

.PARAMETER Count
    Nombre de commandes à générer et injecter (défaut: 10).

.PARAMETER FakerUrl
    URL de base de l'endpoint Faker Java (défaut: http://localhost:9080/demo/api/order).

.PARAMETER TargetUrl
    URL de base de l'API OrderP (défaut: http://localhost:9080/demo/apip/orderp).

.PARAMETER ApiKey
    Clé API transmise dans le header 'X-API-Key' (défaut: demo-api-key-change-me-in-production).

.PARAMETER DelaySeconds
    Délai d'attente (en secondes) entre chaque requête d'injection (défaut: 0).

.PARAMETER Insecure
    Désactive la vérification du certificat SSL/TLS (utile pour certificats auto-signés).

.PARAMETER VerboseOutput
    Affiche les détails complets des requêtes et réponses JSON.

.EXAMPLE
    .\inject-orders.ps1 -Count 20

.EXAMPLE
    .\inject-orders.ps1 -Count 50 -FakerUrl "https://orders-api.apps.mycluster.example.com/demo/api/order" -TargetUrl "https://orders-api.apps.mycluster.example.com/demo/apip/orderp" -ApiKey "my-secret-key"

.EXAMPLE
    .\inject-orders.ps1 -Count 10 -DelaySeconds 0.5 -VerboseOutput
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0, HelpMessage = "Nombre de commandes à générer et injecter")]
    [ValidateRange(1, 1000000)]
    [int]$Count = 10,

    [Parameter(HelpMessage = "URL de base du générateur faker Java")]
    [string]$FakerUrl = $(if ($env:FAKER_URL) { $env:FAKER_URL } else { "http://localhost:9080/demo/api/order" }),

    [Parameter(Alias = "OrderpUrl", HelpMessage = "URL de base de l'API OrderP")]
    [string]$TargetUrl = $(if ($env:ORDERP_URL) { $env:ORDERP_URL } else { "http://localhost:9080/demo/apip/orderp" }),

    [Parameter(HelpMessage = "Clé API pour le header X-API-Key")]
    [string]$ApiKey = $(if ($env:API_KEY) { $env:API_KEY } else { "demo-api-key-change-me-in-production" }),

    [Parameter(HelpMessage = "Délai en secondes entre chaque injection")]
    [ValidateRange(0, 3600)]
    [double]$DelaySeconds = 0,

    [Parameter(HelpMessage = "Désactiver la vérification SSL/TLS")]
    [switch]$Insecure,

    [Parameter(HelpMessage = "Afficher les détails de débogage")]
    [switch]$VerboseOutput
)

# Configuration SSL si Insecure demandé
if ($Insecure) {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell Core (macOS, Linux, Windows) supporte -SkipCertificateCheck sur Invoke-RestMethod
        $sslParam = @{ SkipCertificateCheck = $true }
    } else {
        # Windows PowerShell 5.1
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        $sslParam = @{}
    }
} else {
    $sslParam = @{}
}

# Nettoyage des URLs (suppression du slash final)
$FakerUrl = $FakerUrl.TrimEnd('/')
$TargetUrl = $TargetUrl.TrimEnd('/')

# Masquage de la clé pour affichage
$maskedKey = if ($ApiKey.Length -gt 8) {
    $ApiKey.Substring(0, 4) + "***" + $ApiKey.Substring($ApiKey.Length - 4)
} else {
    "***"
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "       🚀 Génération et Injection de Commandes (OrderP)" -ForegroundColor White
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  • Nombre de commandes : " -NoNewline; Write-Host "$Count" -ForegroundColor Yellow
Write-Host "  • URL Faker (Java)    : " -NoNewline; Write-Host "$FakerUrl" -ForegroundColor Cyan
Write-Host "  • URL Cible (OrderP)  : " -NoNewline; Write-Host "$TargetUrl" -ForegroundColor Cyan
Write-Host "  • Clé API             : " -NoNewline; Write-Host "$maskedKey" -ForegroundColor Gray
Write-Host "  • Délai par requête   : " -NoNewline; Write-Host "$($DelaySeconds)s" -ForegroundColor Gray
Write-Host "  • Vérification TLS    : " -NoNewline;
if ($Insecure) {
    Write-Host "Désactivée (-Insecure)" -ForegroundColor Yellow
} else {
    Write-Host "Activée" -ForegroundColor Green
}
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

$headers = @{
    "X-API-Key" = $ApiKey
    "Accept"    = "application/json"
}

$postHeaders = @{
    "X-API-Key"    = $ApiKey
    "Content-Type" = "application/json"
    "Accept"       = "application/json"
}

$successCount = 0
$failureCount = 0
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

for ($i = 1; $i -le $Count; $i++) {
    $orderGuid = [System.Guid]::NewGuid().ToString()
    $fakerEndpoint = "$FakerUrl/$orderGuid"

    if ($VerboseOutput) {
        Write-Host "[$i/$Count] 📡 Appel du Faker: GET $fakerEndpoint" -ForegroundColor DarkGray
    }

    # 1. Appel au Faker
    $fakeOrderRaw = $null
    try {
        $fakeOrderRaw = Invoke-RestMethod -Uri $fakerEndpoint -Method Get -Headers $headers @sslParam -ErrorAction Stop
    } catch {
        $failureCount++
        Write-Host "[$i/$Count] ❌ Échec Faker: $($_.Exception.Message)" -ForegroundColor Red
        if ($VerboseOutput -and $_.ErrorDetails) {
            Write-Host "           Détails: $($_.ErrorDetails.Message)" -ForegroundColor DarkRed
        }
        continue
    }

    # Extraction des informations pour l'affichage
    $customer = if ($fakeOrderRaw.customer) { $fakeOrderRaw.customer } else { "Inconnu" }
    $region   = if ($fakeOrderRaw.region) { $fakeOrderRaw.region } else { "N/A" }
    $qty      = if ($fakeOrderRaw.quantity) { $fakeOrderRaw.quantity } else { 0 }
    $price    = if ($fakeOrderRaw.price) { $fakeOrderRaw.price } else { 0 }
    $orderId  = if ($fakeOrderRaw.id) { $fakeOrderRaw.id } else { $orderGuid }

    # Conversion en chaîne JSON pour le POST
    $jsonBody = $fakeOrderRaw | ConvertTo-Json -Depth 5 -Compress

    if ($VerboseOutput) {
        Write-Host "[$i/$Count] 📦 Données Faker: $jsonBody" -ForegroundColor DarkGray
        Write-Host "[$i/$Count] 📤 Injection vers OrderP: POST $TargetUrl" -ForegroundColor DarkGray
    }

    # 2. Injection dans OrderP
    try {
        $injectResponse = Invoke-RestMethod -Uri $TargetUrl -Method Post -Headers $postHeaders -Body $jsonBody @sslParam -ErrorAction Stop
        $successCount++
        $shortId = if ($orderId.Length -ge 8) { $orderId.Substring(0, 8) + "..." } else { $orderId }
        Write-Host "[$i/$Count] ✅ ID: $shortId | Client: $customer | Région: $region | Qte: $qty | Prix: `$$price" -ForegroundColor Green
    } catch {
        $failureCount++
        Write-Host "[$i/$Count] ❌ Échec Injection OrderP: $($_.Exception.Message)" -ForegroundColor Red
        if ($VerboseOutput -and $_.ErrorDetails) {
            Write-Host "           Détails: $($_.ErrorDetails.Message)" -ForegroundColor DarkRed
        }
    }

    # Délai optionnel
    if ($DelaySeconds -gt 0) {
        Start-Sleep -Seconds $DelaySeconds
    }
}

$stopwatch.Stop()
$totalSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "                     📊 Résumé de l'exécution" -ForegroundColor White
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  • Total demandé        : $Count"
Write-Host "  • Succès               : " -NoNewline; Write-Host "$successCount" -ForegroundColor Green
Write-Host "  • Échecs               : " -NoNewline
if ($failureCount -gt 0) {
    Write-Host "$failureCount" -ForegroundColor Red
} else {
    Write-Host "0" -ForegroundColor Green
}
Write-Host "  • Durée totale         : $($totalSeconds)s"
Write-Host "=================================================================" -ForegroundColor Cyan

if ($failureCount -gt 0) {
    exit 1
}

exit 0
