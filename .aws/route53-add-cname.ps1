# Route53 Add CNAME Record - Single Command
# Usage: .\route53-add-cname.ps1

param(
    [Parameter(Mandatory=$false)]
    [string]$Subdomain = "mydomain",
    
    [Parameter(Mandatory=$false)]
    [string]$Target = "target.example.com",
    
    [Parameter(Mandatory=$false)]
    [string]$ZoneId = "Z01780191CLMBHU6Y6729",
    
    [Parameter(Mandatory=$false)]
    [string]$Domain = "cjc102.site",
    
    [Parameter(Mandatory=$false)]
    [int]$TTL = 300,
    
    [Parameter(Mandatory=$false)]
    [string]$Profile = "eta"
)

# Create temp JSON file in current directory
$tempFile = ".\temp-change-batch.json"

$changeBatchContent = @"
{
    "Comment": "Add CNAME record for $Subdomain.$Domain",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "$Subdomain.$Domain",
                "Type": "CNAME",
                "TTL": $TTL,
                "ResourceRecords": [
                    {
                        "Value": "$Target"
                    }
                ]
            }
        }
    ]
}
"@

$changeBatchContent | Out-File -FilePath $tempFile -Encoding ASCII

Write-Host "Adding CNAME record: $Subdomain.$Domain -> $Target" -ForegroundColor Cyan
Write-Host "Zone ID: $ZoneId" -ForegroundColor Gray

$env:PAGER = ''
aws route53 change-resource-record-sets --hosted-zone-id $ZoneId --change-batch "file://$tempFile" --profile $Profile

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nCNAME record added successfully!" -ForegroundColor Green
} else {
    Write-Host "`nFailed to add CNAME record. Check your permissions and parameters." -ForegroundColor Red
}

# Cleanup temp file
Remove-Item $tempFile -ErrorAction SilentlyContinue
