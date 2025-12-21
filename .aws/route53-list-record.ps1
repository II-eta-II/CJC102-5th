# List Route53 Records Script
# Usage: .\list-route53-record.ps1 [-ZoneId <zone_id>] [-Profile <profile_name>]

param(
    [Parameter(Mandatory=$false)]
    [string]$ZoneId = "Z01780191CLMBHU6Y6729",
    
    [Parameter(Mandatory=$false)]
    [string]$Profile = "default"
)

# If no ZoneId provided, list all hosted zones first
if ($ZoneId -eq "") {
    Write-Host "`n=== Available Hosted Zones ===" -ForegroundColor Cyan
    aws route53 list-hosted-zones --profile $Profile --query 'HostedZones[*].{Id:Id,Name:Name,RecordCount:ResourceRecordSetCount}' --output table
    
    Write-Host "`nTo list records for a specific zone, run:" -ForegroundColor Yellow
    Write-Host "  .\list-route53-record.ps1 -ZoneId <ZONE_ID>" -ForegroundColor Gray
    Write-Host "`nExample:" -ForegroundColor Yellow
    Write-Host "  .\list-route53-record.ps1 -ZoneId Z01780191CLMBHU6Y6729" -ForegroundColor Gray
    exit
}

# List records for specific zone
Write-Host "`n=== Route53 Records for Zone: $ZoneId ===" -ForegroundColor Cyan
aws route53 list-resource-record-sets --hosted-zone-id $ZoneId --profile $Profile --query 'ResourceRecordSets[*].{Name:Name,Type:Type,TTL:TTL,Values:ResourceRecords[*].Value|join(`, `,@)}' --output table

# Also show alias records
Write-Host "`n=== Alias Records ===" -ForegroundColor Cyan
aws route53 list-resource-record-sets --hosted-zone-id $ZoneId --profile $Profile --query 'ResourceRecordSets[?AliasTarget].{Name:Name,Type:Type,AliasTarget:AliasTarget.DNSName}' --output table
