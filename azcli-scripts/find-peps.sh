#!/bin/bash
# Usage: ./find-peps.sh <resource_name_filter>
# Description: Find Private Endpoints (PEPs) for Azure resources by name filter
# Displays PE details including names, resource groups, and IP addresses

set -e

if [ -z "$1" ]; then
    echo "Error: Resource name filter is required"
    echo "Usage: $0 <resource_name_filter>"
    echo "Example: $0 inztdsaes"
    exit 1
fi

RESOURCE_FILTER="$1"

echo "=================================================="
echo "Searching for resources matching: $RESOURCE_FILTER"
echo "=================================================="
echo ""

# Find resources matching the filter
RESOURCES=$(az resource list --query "[?contains(name, '$RESOURCE_FILTER')].{id:id, name:name, resourceGroup:resourceGroup}" -o json)

if [ "$RESOURCES" == "[]" ] || [ -z "$RESOURCES" ]; then
    echo "No resources found matching filter: $RESOURCE_FILTER"
    exit 0
fi

# Count resources found
RESOURCE_COUNT=$(echo "$RESOURCES" | jq '. | length')
echo "Found $RESOURCE_COUNT resource(s) matching filter"
echo ""

# Track if any PEPs were found
FOUND_PEPS=false

# Process each resource
echo "$RESOURCES" | jq -c '.[]' | while read -r resource; do
    RESOURCE_ID=$(echo "$resource" | jq -r '.id')
    RESOURCE_NAME=$(echo "$resource" | jq -r '.name')
    RESOURCE_RG=$(echo "$resource" | jq -r '.resourceGroup')

    echo "----------------------------------------"
    echo "Resource: $RESOURCE_NAME"
    echo "Resource Group: $RESOURCE_RG"
    echo "Resource ID: $RESOURCE_ID"
    echo ""

    # Find Private Endpoints connected to this resource
    PES=$(az network private-endpoint list --query "[?contains(privateLinkServiceConnections[0].privateLinkServiceId, '$RESOURCE_ID')]" -o json 2>/dev/null || echo "[]")

    if [ "$PES" == "[]" ] || [ -z "$PES" ]; then
        echo "  No Private Endpoints found for this resource"
        echo ""
        continue
    fi

    FOUND_PEPS=true
    PE_COUNT=$(echo "$PES" | jq '. | length')
    echo "  Found $PE_COUNT Private Endpoint(s):"
    echo ""

    # Process each Private Endpoint
    echo "$PES" | jq -c '.[]' | while read -r pe; do
        PE_NAME=$(echo "$pe" | jq -r '.name')
        PE_RG=$(echo "$pe" | jq -r '.resourceGroup')
        PE_LOCATION=$(echo "$pe" | jq -r '.location')

        echo "  ┌─ Private Endpoint: $PE_NAME"
        echo "  │  Resource Group: $PE_RG"
        echo "  │  Location: $PE_LOCATION"

        # Get IP addresses
        IP_ADDRESSES=$(az network private-endpoint show --name "$PE_NAME" --resource-group "$PE_RG" --query "customDnsConfigs[].ipAddresses[]" -o tsv 2>/dev/null || echo "")

        if [ -z "$IP_ADDRESSES" ]; then
            echo "  │  IP Addresses: None found"
        else
            echo "  │  IP Addresses:"
            echo "$IP_ADDRESSES" | while read -r ip; do
                echo "  │    - $ip"
            done
        fi

        # Get FQDN info
        FQDNS=$(az network private-endpoint show --name "$PE_NAME" --resource-group "$PE_RG" --query "customDnsConfigs[].fqdn" -o tsv 2>/dev/null || echo "")

        if [ -n "$FQDNS" ]; then
            echo "  │  FQDNs:"
            echo "$FQDNS" | while read -r fqdn; do
                echo "  │    - $fqdn"
            done
        fi

        echo "  └─"
        echo ""
    done
done

echo "=================================================="
echo "Search complete"
echo "=================================================="
