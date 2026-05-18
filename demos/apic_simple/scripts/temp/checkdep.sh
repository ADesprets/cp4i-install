#!/usr/bin/env bash

# API Deploy Check - Bash Port
# This script validates IBM API Connect core functionality
# The value eyecatcher is used to identify the api in the analytics. It is used as a parameter in the API request and response. It is a random number. The eyecatcher is a unique test marker that proves the API was correctly published, is responding with the right content, and that analytics are properly capturing API calls.


set -euo pipefail

# Constants
MAX_TRIES=15
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
CLIENT_ID="${CLIENT_ID:-599b7aef-8841-4ee2-88a0-84d49c4d6ff2}"
CLIENT_SECRET="${CLIENT_SECRET:-0ea28423-e73b-47d4-b40e-ddb45c48bb0c}"
REALM="${APIC_REALM:-provider/default-idp-2}"
FILENAME="set-variable.yaml"
VERIFY_SSL=true
V12_MODE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
function log_info() {
    echo -e "${GREEN}INFO:${NC} $*" >&2
}

function log_warning() {
    echo -e "${YELLOW}WARNING:${NC} $*" >&2
}

function log_error() {
    echo -e "${RED}ERROR:${NC} $*" >&2
}

function log_critical() {
    echo -e "${RED}CRITICAL:${NC} $*" >&2
}

function log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}DEBUG:${NC} $*" >&2
    fi
}

# Product YAML template
read -r -d '' PRODUCT_YAML <<'EOF' || true
info:
  version: 2.0.0
  title: 'Publish Test Product'
  name: publish-test-product
apis:
  publish-test:
    name: publish-test:1.0.1
gateways:
  - datapower-api-gateway
plans:
  default-plan:
    title: Default Plan
    description: Default Plan
    approval: false
    rate-limits:
      default:
        value: 100/1hour
product: 1.0.0
visibility:
  view:
    enabled: true
    type: public
    tags: []
    orgs: []
  subscribe:
    enabled: true
    type: authenticated
    tags: []
    orgs: []
EOF

# Usage function
function usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
    -s, --server HOST          Platform API hostname (required)
    -o, --org ORG             Organization (required)
    -c, --catalog CATALOG     Catalog (required)
    --verify                  Verify SSL certificates (default: true)
    --no-verify               Don't verify SSL certificates
    -a, --apikey KEY          API Key (or set APIC_API_KEY env var)
    -u, --username USER       Username (or set APIC_USERNAME env var)
    -p, --password PASS       Password (or set APIC_PASSWORD env var)
    -r, --realm REALM         Realm (default: provider/default-idp-2)
    --client-id ID            Client ID for token retrieval
    --client-secret SECRET    Client secret for token retrieval
    -f, --filename FILE       API template file (default: set-variable.yaml)
    --v12                     Use v12 API publish flow
    --debug                   Enable debug output
    -h, --help                Show this help message

Examples:
    # Using API Key
    $0 -s apim.example.com -o myorg -c sandbox -a \$APIC_API_KEY

    # Using username/password
    $0 -s apim.example.com -o myorg -c sandbox -u admin -p password

    # Using v12 API format
    $0 -s apim.example.com -o myorg -c sandbox -a \$APIC_API_KEY --v12

EOF
    exit 1
}

# Parse command line arguments
function parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--server)
                SERVER="$2"
                shift 2
                ;;
            -o|--org)
                ORG="$2"
                shift 2
                ;;
            -c|--catalog)
                CATALOG="$2"
                shift 2
                ;;
            --verify)
                VERIFY_SSL=true
                shift
                ;;
            --no-verify)
                VERIFY_SSL=false
                shift
                ;;
            -a|--apikey)
                APIKEY="$2"
                shift 2
                ;;
            -u|--username)
                USERNAME="$2"
                shift 2
                ;;
            -p|--password)
                PASSWORD="$2"
                shift 2
                ;;
            -r|--realm)
                REALM="$2"
                shift 2
                ;;
            --client-id)
                CLIENT_ID="$2"
                shift 2
                ;;
            --client-secret)
                CLIENT_SECRET="$2"
                shift 2
                ;;
            -f|--filename)
                FILENAME="$2"
                shift 2
                ;;
            --v12)
                V12_MODE=true
                shift
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Check required parameters
    if [[ -z "${SERVER:-}" ]]; then
        log_error "Server hostname is required"
        usage
    fi
    if [[ -z "${ORG:-}" ]]; then
        log_error "Organization is required"
        usage
    fi
    if [[ -z "${CATALOG:-}" ]]; then
        log_error "Catalog is required"
        usage
    fi

    # Check authentication
    APIKEY="${APIKEY:-${APIC_API_KEY:-}}"
    USERNAME="${USERNAME:-${APIC_USERNAME:-}}"
    PASSWORD="${PASSWORD:-${APIC_PASSWORD:-}}"

    if [[ -z "${APIKEY}" && -z "${PASSWORD}" ]]; then
        log_error "Either API key or username/password is required"
        usage
    fi
}

# Get curl SSL options
function get_curl_ssl_opts() {
    if [[ "${VERIFY_SSL}" == "false" ]]; then
        echo "-k"
    else
        echo ""
    fi
}

# Generate random eyecatcher string
function generate_eyecatcher() {
    LC_ALL=C tr -dc 'A-Z0-9' < /dev/urandom | head -c 25
}

# Get authentication token
function get_token() {
    local hostname="$1"
    local token_request

    if [[ -n "${APIKEY}" ]]; then
        # Use API Key
        token_request=$(jq -n \
            --arg client_id "$CLIENT_ID" \
            --arg client_secret "$CLIENT_SECRET" \
            --arg api_key "$APIKEY" \
            '{
                client_id: $client_id,
                client_secret: $client_secret,
                api_key: $api_key,
                grant_type: "api_key"
            }')
    elif [[ -n "${PASSWORD}" ]]; then
        # Use username/password
        token_request=$(jq -n \
            --arg client_id "$CLIENT_ID" \
            --arg client_secret "$CLIENT_SECRET" \
            --arg username "$USERNAME" \
            --arg password "$PASSWORD" \
            --arg realm "$REALM" \
            '{
                client_id: $client_id,
                client_secret: $client_secret,
                username: $username,
                password: $password,
                realm: $realm,
                grant_type: "password"
            }')
    else
        log_critical "No authentication method available"
        return 1
    fi

    local response
    local status_code
    
    response=$(curl -s -w "\n%{http_code}" $(get_curl_ssl_opts) \
        -X POST \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "$token_request" \
        "https://${hostname}/api/token")
    
    status_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [[ "$status_code" == "200" ]]; then
        log_info "Retrieve token - status: $status_code"
        echo "$body" | jq -r '.access_token'
        return 0
    else
        log_error "Retrieve token - status: $status_code, response: $body"
        return 1
    fi
}

# Publish API (non-v12)
function publish_api() {
    local hostname="$1"
    local token="$2"
    local org="$3"
    local catalog="$4"
    local eyecatcher="$5"
    local filename="$6"
    
    local template_path="${SCRIPT_DIR}/templates/${filename}"
    
    if [[ ! -f "$template_path" ]]; then
        log_error "Template file not found: $template_path"
        return 1
    fi
    
    # Read and process API definition
    local api_definition=$(sed "s/RESPONSE/${eyecatcher}/g" "$template_path")
    
    # Extract API name from YAML
    local api_name=$(echo "$api_definition" | grep -A1 "x-ibm-name:" | tail -n1 | sed 's/.*: *//')
    local api_version=$(echo "$api_definition" | grep -A2 "^info:" | grep "version:" | sed 's/.*: *//')
    api_name="${api_name}:${api_version}"
    
    # Update product definition with correct API name
    local product_definition=$(echo "$PRODUCT_YAML" | sed "s/publish-test:1.0.1/${api_name}/")
    
    log_debug "API Definition:"
    log_debug "$api_definition"
    
    # Create temporary files for multipart upload
    local temp_dir=$(mktemp -d)
    echo "$product_definition" > "${temp_dir}/product.yaml"
    echo "$api_definition" > "${temp_dir}/openapi.yaml"
    
    local response
    local status_code
    
    response=$(curl -s -w "\n%{http_code}" $(get_curl_ssl_opts) \
        -X POST \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/json" \
        -F "product=@${temp_dir}/product.yaml;type=application/yaml" \
        -F "openapi=@${temp_dir}/openapi.yaml;type=application/yaml" \
        "https://${hostname}/api/catalogs/${org}/${catalog}/publish")
    
    status_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    # Cleanup temp files
    rm -rf "$temp_dir"
    
    log_info "Publish API - status code: $status_code"
    
    if echo "$body" | jq -e '.updated_at' > /dev/null 2>&1; then
        local updated_at=$(echo "$body" | jq -r '.updated_at')
        log_info "Publish response shows updated at: $updated_at"
        echo "$api_name"
        return 0
    else
        log_error "Publish failed: $body"
        return 1
    fi
}

# Publish API v12
function publish_api_v12() {
    local hostname="$1"
    local token="$2"
    local org="$3"
    local catalog="$4"
    local eyecatcher="$5"
    
    local api_yaml_path="${SCRIPT_DIR}/templates/v12/quick-api.yml"
    
    if [[ ! -f "$api_yaml_path" ]]; then
        log_error "v12 API template not found: $api_yaml_path"
        return 1
    fi
    
    # Read API definition and replace eyecatcher
    local api_definition=$(sed "s/RESPONSE/${eyecatcher}/g" "$api_yaml_path")
    
    # Detect project name from resources directory
    local resources_dir="${SCRIPT_DIR}/templates/v12/resources"
    local project_name=$(ls -1 "$resources_dir" | head -n1)
    
    if [[ -z "$project_name" ]]; then
        log_error "Could not find project directory in resources/"
        return 1
    fi
    
    log_info "Detected project name from resources directory: $project_name"
    
    local spec_path="${resources_dir}/${project_name}/quick-api-spec.yml"
    if [[ ! -f "$spec_path" ]]; then
        log_error "Spec file not found: $spec_path"
        return 1
    fi
    
    local spec_yaml=$(cat "$spec_path")
    
    log_debug "API Definition:"
    log_debug "$api_definition"
    
    # Extract API name and version from YAML
    local api_name=$(echo "$api_definition" | grep -A3 "kind: API" | grep "name:" | head -n1 | sed 's/.*name: *//')
    local api_version=$(echo "$api_definition" | grep -A4 "kind: API" | grep "version:" | head -n1 | sed 's/.*version: *//' | tr -d "'\"")
    local full_api_name="${api_name}:${api_version}"
    
    # Create zip file
    local zip_path="/tmp/api_${RANDOM}.zip"
    log_debug "Creating zip file at: $zip_path"
    
    # Create temporary directory structure
    local temp_dir=$(mktemp -d)
    echo "$api_definition" > "${temp_dir}/${project_name}.yaml"
    mkdir -p "${temp_dir}/resources/${project_name}"
    echo "$spec_yaml" > "${temp_dir}/resources/${project_name}/quick-api-spec.yml"
    
    # Create zip
    (cd "$temp_dir" && zip -r "$zip_path" . > /dev/null)
    
    local zip_size=$(stat -f%z "$zip_path" 2>/dev/null || stat -c%s "$zip_path" 2>/dev/null)
    log_info "Created project zip file at $zip_path with size: $zip_size bytes"
    
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log_debug "Zip file contents:"
        unzip -l "$zip_path" | while read -r line; do
            log_debug "  $line"
        done
    fi
    
    # Cleanup temp directory
    rm -rf "$temp_dir"
    
    log_debug "Project name (from namespace): $project_name"
    log_debug "Spec location in zip: resources/$project_name/quick-api-spec.yml"
    
    # Publish the API
    local response
    local status_code
    
    response=$(curl -s -w "\n%{http_code}" $(get_curl_ssl_opts) \
        -X POST \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/json" \
        -F "project=@${zip_path};type=application/zip" \
        "https://${hostname}/api/catalogs/${org}/${catalog}/publish-project")
    
    status_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    # Cleanup zip file
    rm -f "$zip_path"
    
    log_info "Publish v12 API - status code: $status_code"
    
    local req_id=$(echo "$response" | grep -i "x-request-id:" | sed 's/.*: *//' || echo "Not present")
    log_info "X-Request-Id: $req_id"
    
    if [[ "$status_code" == "200" || "$status_code" == "201" ]]; then
        log_info "Publish response: $body"
        
        # Extract gateway endpoint
        local gateway_endpoint=$(echo "$body" | jq -r '.results[0].gateway_endpoints[0] // empty')
        if [[ -n "$gateway_endpoint" ]]; then
            log_info "Gateway endpoint from response: $gateway_endpoint"
        fi
        
        echo "${full_api_name}|${gateway_endpoint}"
        return 0
    else
        log_error "Failed to publish v12 API: $body"
        return 1
    fi
}

# Get catalog details
function get_catalog_details() {
    local hostname="$1"
    local token="$2"
    local org="$3"
    local catalog="$4"
    
    local response
    local status_code
    
    response=$(curl -s -w "\n%{http_code}" $(get_curl_ssl_opts) \
        -X GET \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/json" \
        "https://${hostname}/api/catalogs/${org}/${catalog}/configured-gateway-services")
    
    status_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [[ "$status_code" != "200" ]]; then
        log_error "Failed to get catalog details: $body"
        return 1
    fi
    
    local total_results=$(echo "$body" | jq -r '.total_results')
    if [[ "$total_results" -gt 1 ]]; then
        local title=$(echo "$body" | jq -r '.results[0].title')
        log_warning "Catalog has multiple gateway services defined, using $title"
    fi
    
    local analytics=$(echo "$body" | jq -r '.results[0].analytics_service_url' | sed 's|.*/||')
    local api_base=$(echo "$body" | jq -r '.results[0].catalog_base')
    
    echo "${analytics}|${api_base}"
}

# Get analytics records
function get_analytics_records() {
    local hostname="$1"
    local token="$2"
    local org="$3"
    local catalog="$4"
    local a7s="$5"
    local api_name="$6"
    
    local response
    local status_code
    
    response=$(curl -s -w "\n%{http_code}" $(get_curl_ssl_opts) \
        -X GET \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/json" \
        "https://${hostname}/analytics/${a7s}/catalogs/${org}/${catalog}/events?api_name=${api_name}&timeframe=last15minutes")
    
    status_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    local req_id=$(echo "$response" | grep -i "x-request-id:" | sed 's/.*: *//' || echo "unknown")
    
    echo "${body}|${req_id}"
}

# Main deployment test function
function deploy_test() {
    log_info "Starting API deployment test"
    log_info "Server: $SERVER"
    
    # Get authentication token
    local token
    token=$(get_token "$SERVER")
    
    if [[ -z "$token" ]]; then
        log_critical "Unable to retrieve token"
        return 4
    fi
    
    # Generate eyecatcher
    local eyecatcher=$(generate_eyecatcher)
    log_info "Eyecatcher for API is: $eyecatcher"
    
    # Publish API
    local api_name
    local gateway_endpoint=""
    
    if [[ "$V12_MODE" == "true" ]]; then
        local result
        result=$(publish_api_v12 "$SERVER" "$token" "$ORG" "$CATALOG" "$eyecatcher")
        if [[ $? -ne 0 ]]; then
            return 8
        fi
        api_name=$(echo "$result" | cut -d'|' -f1)
        gateway_endpoint=$(echo "$result" | cut -d'|' -f2)
    else
        api_name=$(publish_api "$SERVER" "$token" "$ORG" "$CATALOG" "$eyecatcher" "$FILENAME")
        if [[ $? -ne 0 ]]; then
            return 8
        fi
    fi
    
    log_debug "API name: $api_name"
    
    # Get catalog details
    local catalog_info
    catalog_info=$(get_catalog_details "$SERVER" "$token" "$ORG" "$CATALOG")
    if [[ $? -ne 0 ]]; then
        return 8
    fi
    
    local analytics=$(echo "$catalog_info" | cut -d'|' -f1)
    local api_base=$(echo "$catalog_info" | cut -d'|' -f2)
    
    # Determine API URL
    local new_api
    if [[ "$V12_MODE" == "true" && -n "$gateway_endpoint" ]]; then
        new_api="$gateway_endpoint"
        log_info "Using gateway endpoint from publish response: $new_api"
    else
        local api_base_path
        if [[ "$V12_MODE" == "true" ]]; then
            api_base_path="quick"
        else
            api_base_path="publish-test"
        fi
        new_api="${api_base}/${api_base_path}"
        log_info "Published API URL: $new_api"
    fi
    
    # Test API invocation
    local attempt=0
    local updated=false
    local x_gtid=""
    
    while [[ $attempt -lt $MAX_TRIES ]]; do
        ((attempt++))
        
        local response
        local status_code
        
        response=$(curl -s -w "\n%{http_code}" $(get_curl_ssl_opts) \
            -X GET \
            -D - \
            "${new_api}?eyecatcher=${eyecatcher}&attempt=${attempt}")
        
        status_code=$(echo "$response" | tail -n1)
        local headers=$(echo "$response" | sed '$d' | sed '/^$/q')
        local body=$(echo "$response" | sed '$d' | sed '1,/^$/d')
        
        x_gtid=$(echo "$headers" | grep -i "x-global-transaction-id:" | sed 's/.*: *//' | tr -d '\r\n')
        
        if echo "$body" | grep -q "$eyecatcher"; then
            log_info "Invoke $attempt / $MAX_TRIES: status: $status_code, response: ${body:0:50}, GTID: $x_gtid - Successful match!"
            log_info "API response matches for $eyecatcher"
            updated=true
            break
        fi
        
        log_warning "Invoke $attempt / $MAX_TRIES: status: $status_code, response: ${body:0:50}, GTID: $x_gtid"
        sleep 5
    done
    
    if [[ "$updated" != "true" ]]; then
        log_critical "API not updated after $((MAX_TRIES * 5)) seconds"
        return 2
    fi
    
    log_info "API is updated"
    
    # Check analytics
    attempt=0
    local found=false
    
    while [[ $attempt -lt $MAX_TRIES ]]; do
        ((attempt++))
        
        local analytics_result
        analytics_result=$(get_analytics_records "$SERVER" "$token" "$ORG" "$CATALOG" "$analytics" "$api_name")
        
        local events=$(echo "$analytics_result" | cut -d'|' -f1)
        local req_id=$(echo "$analytics_result" | cut -d'|' -f2)
        local total=$(echo "$events" | jq -r '.total // 0')
        
        # Check if our transaction ID is in the events
        if echo "$events" | jq -e ".events[] | select(.global_transaction_id == \"$x_gtid\")" > /dev/null 2>&1; then
            log_info "Analytics $attempt / $MAX_TRIES: events: $total, request_id $req_id - Transaction ID found"
            log_info "Matched transaction id ($x_gtid) of successful call in analytics"
            
            local time_to_serve=$(echo "$events" | jq -r ".events[] | select(.global_transaction_id == \"$x_gtid\") | .time_to_serve_request")
            local query_string=$(echo "$events" | jq -r ".events[] | select(.global_transaction_id == \"$x_gtid\") | .query_string")
            log_info "API response in ${time_to_serve}ms for $query_string"
            
            found=true
            break
        fi
        
        log_warning "Analytics $attempt / $MAX_TRIES: events: $total, request_id $req_id"
        sleep 5
    done
    
    if [[ "$found" != "true" ]]; then
        log_critical "API record not in analytics after $((MAX_TRIES * 5)) seconds"
        return 1
    fi
    
    log_info "Test completed successfully!"
    return 0
}

# Main execution
function main() {
    # Check dependencies
    for cmd in curl jq zip; do
        if ! command -v "$cmd" &> /dev/null; then
            log_critical "Required command not found: $cmd"
            log_critical "Please install: $cmd"
            exit 5
        fi
    done
    
    parse_args "$@"
    deploy_test
    exit $?
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Made with Bob
