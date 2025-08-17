#!/bin/bash

# ############################################################################ #
# Configuration Validation Script                                             #
# Validate server configurations and check prerequisites                      #
# Usage: ./scripts/validate.sh <server>                                       #
# ############################################################################ #

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
Usage: $0 <server>

Arguments:
    server          Server name to validate (e.g., lugia, snorlax)

Examples:
    $0 lugia        # Validate lugia server configuration
    $0 snorlax      # Validate snorlax server configuration
EOF
}

# Check if required tools are installed
check_dependencies() {
    local missing_deps=()

    log_info "Checking dependencies..."

    # Check for required tools
    local deps=("docker" "python3" "age" "yq")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Install missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                docker)
                    echo "  - Docker: https://docs.docker.com/get-docker/"
                    ;;
                python3)
                    echo "  - Python 3: apt install python3-pip (Ubuntu) or brew install python3 (macOS)"
                    ;;
                age)
                    echo "  - Age: apt install age (Ubuntu) or brew install age (macOS)"
                    ;;
                yq)
                    echo "  - yq: apt install yq (Ubuntu) or brew install yq (macOS)"
                    ;;
            esac
        done
        return 1
    fi

    log_success "All dependencies are installed"
}

# Validate YAML syntax
validate_yaml_syntax() {
    local config_file="$1"
    
    log_info "Validating YAML syntax..."
    
    if ! python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
        log_error "Invalid YAML syntax in $config_file"
        return 1
    fi
    
    log_success "YAML syntax is valid"
}

# Validate server configuration structure
validate_config_structure() {
    local config_file="$1"
    
    log_info "Validating configuration structure..."
    
    # Check required fields
    python3 << EOF
import yaml
import sys

required_fields = {
    'server': ['name', 'type', 'domain', 'internal_domain'],
    'volumes': ['config_base', 'data_base', 'downloads_base'],
    'environment': ['TZ', 'PUID', 'PGID'],
    'cloudflare': ['tunnel_name'],
    'stacks': ['enabled']
}

try:
    with open('$config_file', 'r') as f:
        config = yaml.safe_load(f)
    
    errors = []
    
    for section, fields in required_fields.items():
        if section not in config:
            errors.append(f"Missing section: {section}")
            continue
            
        for field in fields:
            if field not in config[section]:
                errors.append(f"Missing field: {section}.{field}")
    
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        sys.exit(1)
    else:
        print("Configuration structure is valid")

except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
EOF

    if [[ $? -eq 0 ]]; then
        log_success "Configuration structure is valid"
    else
        log_error "Configuration structure validation failed"
        return 1
    fi
}

# Validate stack references
validate_stacks() {
    local config_file="$1"
    
    log_info "Validating stack references..."
    
    python3 << EOF
import yaml
import os

with open('$config_file', 'r') as f:
    config = yaml.safe_load(f)

stacks_dir = '$PROJECT_DIR/docker/stacks'
enabled_stacks = config['stacks']['enabled']
errors = []

for stack in enabled_stacks:
    stack_path = os.path.join(stacks_dir, stack)
    compose_file = os.path.join(stack_path, 'docker-compose.yml')
    
    if not os.path.exists(stack_path):
        errors.append(f"Stack directory not found: {stack}")
    elif not os.path.exists(compose_file):
        errors.append(f"Docker compose file not found: {stack}/docker-compose.yml")

if errors:
    for error in errors:
        print(f"ERROR: {error}")
    exit(1)
else:
    print(f"All {len(enabled_stacks)} enabled stacks are valid")
EOF

    if [[ $? -eq 0 ]]; then
        log_success "Stack references are valid"
    else
        log_error "Stack validation failed"
        return 1
    fi
}

# Check Docker daemon
check_docker() {
    log_info "Checking Docker daemon..."
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        log_info "Start Docker daemon: sudo systemctl start docker"
        return 1
    fi
    
    log_success "Docker daemon is running"
}

# Validate domain format
validate_domains() {
    local config_file="$1"
    
    log_info "Validating domain formats..."
    
    python3 << EOF
import yaml
import re

with open('$config_file', 'r') as f:
    config = yaml.safe_load(f)

domain_pattern = r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'

domain = config['server']['domain']
internal_domain = config['server']['internal_domain']

errors = []

if not re.match(domain_pattern, domain):
    errors.append(f"Invalid domain format: {domain}")

if not internal_domain.endswith('.local'):
    errors.append(f"Internal domain should end with .local: {internal_domain}")

if errors:
    for error in errors:
        print(f"ERROR: {error}")
    exit(1)
else:
    print("Domain formats are valid")
EOF

    if [[ $? -eq 0 ]]; then
        log_success "Domain formats are valid"
    else
        log_error "Domain validation failed"
        return 1
    fi
}

# Check secrets
check_secrets() {
    local server="$1"
    local secrets_file="$PROJECT_DIR/secrets/$server.env.age"
    
    log_info "Checking secrets..."
    
    if [[ ! -f "$secrets_file" ]]; then
        log_warning "No encrypted secrets found: $secrets_file"
        log_info "Generate secrets: ./scripts/secrets.sh generate $server"
        return 1
    fi
    
    # Try to decrypt to verify key access
    if ! age -d -i "$HOME/.age/key.txt" "$secrets_file" &> /dev/null; then
        log_error "Cannot decrypt secrets file (check age key)"
        return 1
    fi
    
    log_success "Secrets file is accessible"
}

# Validate volume paths
validate_volumes() {
    local config_file="$1"
    
    log_info "Validating volume paths..."
    
    python3 << EOF
import yaml
import os

with open('$config_file', 'r') as f:
    config = yaml.safe_load(f)

volumes = config['volumes']
warnings = []

for name, path in volumes.items():
    # Check if path is absolute
    if not os.path.isabs(path):
        warnings.append(f"Volume path should be absolute: {name}={path}")
    
    # Check if parent directory exists (for local validation)
    parent = os.path.dirname(path)
    if os.path.exists(parent) and not os.access(parent, os.W_OK):
        warnings.append(f"Parent directory not writable: {parent}")

if warnings:
    for warning in warnings:
        print(f"WARNING: {warning}")
else:
    print("Volume paths look good")
EOF

    log_success "Volume path validation completed"
}

# Generate validation report
generate_report() {
    local server="$1"
    local config_file="$PROJECT_DIR/configs/servers/$server.yml"
    
    echo
    log_info "=== Validation Report for $server ==="
    
    python3 << EOF
import yaml

with open('$config_file', 'r') as f:
    config = yaml.safe_load(f)

server_info = config['server']
stacks = config['stacks']

print(f"Server: {server_info['name']} ({server_info['type']})")
print(f"Domain: {server_info['domain']}")
print(f"Internal Domain: {server_info['internal_domain']}")
print(f"Enabled Stacks: {len(stacks['enabled'])}")

print("\nEnabled Services:")
for stack in stacks['enabled']:
    print(f"  - {stack}")

if 'external_services' in config:
    print(f"\nExternal Services: {len(config['external_services'])}")
    for service in config['external_services']:
        print(f"  - {service}-{server_info['name']}.{server_info['domain']}")
EOF
    
    echo
}

# Main validation function
main() {
    if [[ $# -ne 1 ]]; then
        usage
        exit 1
    fi

    local server="$1"
    local config_file="$PROJECT_DIR/configs/servers/$server.yml"

    if [[ ! -f "$config_file" ]]; then
        log_error "Server configuration not found: $config_file"
        log_info "Available servers:"
        ls -1 "$PROJECT_DIR/configs/servers/"*.yml 2>/dev/null | xargs -n1 basename | sed 's/.yml$//' || echo "No server configurations found"
        exit 1
    fi

    log_info "Validating configuration for server: $server"
    echo

    local validation_failed=false

    # Run all validations
    check_dependencies || validation_failed=true
    validate_yaml_syntax "$config_file" || validation_failed=true
    validate_config_structure "$config_file" || validation_failed=true
    validate_stacks "$config_file" || validation_failed=true
    validate_domains "$config_file" || validation_failed=true
    validate_volumes "$config_file" || validation_failed=true
    check_docker || validation_failed=true
    check_secrets "$server" || validation_failed=true

    # Generate report
    generate_report "$server"

    if [[ "$validation_failed" == "true" ]]; then
        log_error "Validation failed for $server"
        exit 1
    else
        log_success "All validations passed for $server"
    fi
}

main "$@"