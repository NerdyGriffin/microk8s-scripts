#!/bin/bash

# A script to convert a Kubernetes Endpoints object to an EndpointSlice.
# This is useful for migrating manually managed endpoints for selectorless services.
# Requires: kubectl and jq

# Exit immediately if a command exits with a non-zero status.
set -e

# Validate the command-line arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <endpoints_name> <namespace>"
    exit 1
fi

ENDPOINT_NAME="$1"
NAMESPACE="$2"
ENDPOINT_SLICE_NAME="${ENDPOINT_NAME}-slice"
SERVICE_NAME="${ENDPOINT_NAME}"

echo "Fetching Endpoints object '$ENDPOINT_NAME' in namespace '$NAMESPACE'..."
ENDPOINT_DATA=$(kubectl get endpoints "$ENDPOINT_NAME" -n "$NAMESPACE" -o json)

# Check if endpoints data was retrieved successfully
if [ -z "$ENDPOINT_DATA" ]; then
    echo "Error: Could not find Endpoints object '$ENDPOINT_NAME' in namespace '$NAMESPACE'."
    exit 1
fi

# Extract relevant data using jq
SUBSETS=$(echo "$ENDPOINT_DATA" | jq -c '.subsets')

# Start building the EndpointSlice manifest
ENDPOINT_SLICE_MANIFEST=$(cat <<EOF
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: ${ENDPOINT_SLICE_NAME}
  namespace: ${NAMESPACE}
  labels:
    kubernetes.io/service-name: ${SERVICE_NAME}
addressType: IPv4
ports: []
endpoints: []
EOF
)

# Function to add endpoints and ports to the manifest
# Note: This script only handles IPv4 and assumes all subsets share the same ports.
# For more complex scenarios, the jq logic would need to be more sophisticated.
NEW_ENDPOINTS=""
NEW_PORTS=""

# Extract endpoints from subsets. Each subset in the Endpoints object becomes an entry in the EndpointSlice.
if [[ $(echo "$SUBSETS" | jq '. | length') -gt 0 ]]; then
    NEW_ENDPOINTS=$(echo "$SUBSETS" | jq -c '
        .[] | {
            addresses: [.addresses[].ip],
            conditions: {
                ready: true
            }
        }' | jq -s '.')

    NEW_PORTS=$(echo "$SUBSETS" | jq -c '
        .[] | .ports[] | {
            name: .name,
            port: .port,
            protocol: .protocol
        }' | jq -s '.')
fi

# Inject the extracted data into the manifest template using a temporary file
TEMP_MANIFEST=$(mktemp)
echo "$ENDPOINT_SLICE_MANIFEST" > "$TEMP_MANIFEST"

if [ -n "$NEW_ENDPOINTS" ]; then
    # Add endpoints
    jq --argjson new_endpoints "$NEW_ENDPOINTS" '.endpoints += $new_endpoints' "$TEMP_MANIFEST" > "$TEMP_MANIFEST.tmp" && mv "$TEMP_MANIFEST.tmp" "$TEMP_MANIFEST"
fi

if [ -n "$NEW_PORTS" ]; then
    # Add ports
    jq --argjson new_ports "$NEW_PORTS" '.ports += $new_ports' "$TEMP_MANIFEST" > "$TEMP_MANIFEST.tmp" && mv "$TEMP_MANIFEST.tmp" "$TEMP_MANIFEST"
fi
echo "Example created at $TEST_MANIFEST"

# # Apply the new EndpointSlice manifest
# echo "Creating EndpointSlice '$ENDPOINT_SLICE_NAME' in namespace '$NAMESPACE'..."
# kubectl apply -f "$TEMP_MANIFEST"

# echo "Cleanup temporary files..."
# rm "$TEMP_MANIFEST"

echo "EndpointSlice creation complete."
echo "You can verify with: kubectl get endpointslices -n $NAMESPACE"
