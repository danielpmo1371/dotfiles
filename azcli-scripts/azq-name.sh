#!/bin/bash
# Usage: ./azq.sh <resource_name_filter>
# Description: Query Azure resources by name filter and display in table format

if [ -z "$1" ]; then
  echo "Error: Resource name filter is required"
  echo "Usage: $0 <resource_name_filter>"
  echo "Example: $0 inztdsaes"
  exit 1
fi

RESOURCE_FILTER="$1"

az resource list --query "[?contains(name, '$RESOURCE_FILTER')].{name:name, resourceGroup:resourceGroup}" -o table
