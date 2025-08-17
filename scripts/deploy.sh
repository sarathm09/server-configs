#!/bin/bash

# ############################################################################ #
# Server Deployment Script                                                    #
# Deploy services to servers based on YAML configuration                      #
# Usage: ./scripts/deploy.sh <server> [--stack=<stack>] [--domain=<domain>]   #
# ############################################################################ #

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
SERVER=""
STACK=""
DOMAIN_OVERRIDE=""
DRY_RUN=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 <server> [OPTIONS]

Arguments:
    server          Server name (e.g., lugia, snorlax)

Options:
    --stack=STACK   Deploy specific stack only
    --domain=DOMAIN Override domain from config
    --dry-run       Show what would be deployed without executing
    --help          Show this help message

Examples:
    $0 lugia                    # Deploy all enabled stacks to lugia
    $0 snorlax --stack=06-media-nexus  # Deploy only media stack to snorlax
    $0 lugia --domain=example.com      # Override domain for lugia
EOF
}

# Parse command line arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    SERVER="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case $1 in
            --stack=*)
                STACK="${1#*=}"
                shift
                ;;
            --domain=*)
                DOMAIN_OVERRIDE="${1#*=}"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$SERVER" ]]; then
        log_error "Server name is required"
        usage
        exit 1
    fi
}

# Validate server configuration
validate_config() {
    local config_file="$PROJECT_DIR/configs/servers/$SERVER.yml"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Server configuration not found: $config_file"
        log_info "Available servers:"
        ls -1 "$PROJECT_DIR/configs/servers/"*.yml 2>/dev/null | xargs -n1 basename | sed 's/.yml$//'
        exit 1
    fi

    log_info "Using configuration: $config_file"
}

# Generate environment file from server config
generate_env() {
    local config_file="$PROJECT_DIR/configs/servers/$SERVER.yml"
    local env_dir="$PROJECT_DIR/docker/env/$SERVER"
    local env_file="$env_dir/.env"

    log_info "Generating environment file for $SERVER..."
    
    # Create env directory
    mkdir -p "$env_dir"

    # Parse YAML and generate .env file
    python3 << EOF
import yaml
import os

# Load server configuration
with open('$config_file', 'r') as f:
    config = yaml.safe_load(f)

# Extract values
server = config['server']
volumes = config['volumes']
environment = config['environment']

# Generate .env content
env_content = []

# Server information
env_content.append(f"# Server configuration for {server['name']}")
env_content.append(f"SERVER_NAME={server['name']}")
env_content.append(f"SERVER_TYPE={server['type']}")
env_content.append(f"DOMAIN={server.get('domain', '$DOMAIN_OVERRIDE' if '$DOMAIN_OVERRIDE' else 'localhost')}")
env_content.append(f"INTERNAL_DOMAIN={server['internal_domain']}")
env_content.append("")

# Volume mappings
env_content.append("# Volume mappings")
for key, value in volumes.items():
    env_content.append(f"{key.upper()}={value}")
env_content.append("")

# Environment variables
env_content.append("# Environment variables")
for key, value in environment.items():
    env_content.append(f"{key}={value}")
env_content.append("")

# Network names
env_content.append("# Network configuration")
env_content.append(f"{server['name'].upper()}_NETWORK={server['name']}-network")
env_content.append(f"{server['name'].upper()}_PROXY={server['name']}-proxy")

# Write to file
with open('$env_file', 'w') as f:
    f.write('\n'.join(env_content))

print("Environment file generated successfully")
EOF

    # Override domain if specified
    if [[ -n "$DOMAIN_OVERRIDE" ]]; then
        sed -i "s/DOMAIN=.*/DOMAIN=$DOMAIN_OVERRIDE/" "$env_file"
    fi

    # Decrypt and merge secrets
    merge_secrets_to_env

    log_success "Environment file created: $env_file"
}

# Decrypt secrets and merge them into the .env file
merge_secrets_to_env() {
    local env_file="$PROJECT_DIR/docker/env/$SERVER/.env"
    local secrets_file="$PROJECT_DIR/secrets/$SERVER.env.age"
    local decrypted_secrets_file="$PROJECT_DIR/docker/env/$SERVER/secrets.env"
    local age_key="$HOME/.age/key.txt"

    log_info "Merging secrets into environment file..."

    # Check if decrypted secrets file already exists and is newer than encrypted file
    if [[ -f "$decrypted_secrets_file" && -f "$secrets_file" ]]; then
        if [[ "$decrypted_secrets_file" -nt "$secrets_file" ]]; then
            log_info "Using existing decrypted secrets file"
            cat "$decrypted_secrets_file" >> "$env_file"
            echo "" >> "$env_file"  # Add newline separator
            log_success "Existing secrets merged successfully"
            return 0
        fi
    fi

    # Check if encrypted secrets file exists
    if [[ ! -f "$secrets_file" ]]; then
        log_warning "No encrypted secrets found: $secrets_file"
        log_info "Run: ./scripts/secrets.sh generate $SERVER"
        return 0
    fi

    # Check if age key exists
    if [[ ! -f "$age_key" ]]; then
        log_error "Age private key not found: $age_key"
        log_info "Run: ./scripts/secrets.sh generate $SERVER to create keys"
        return 1
    fi

    # Decrypt secrets to temporary file first, then append to .env file
    if age -d -i "$age_key" "$secrets_file" > "$decrypted_secrets_file" 2>/dev/null; then
        cat "$decrypted_secrets_file" >> "$env_file"
        echo "" >> "$env_file"  # Add newline separator
        log_success "Secrets decrypted and merged successfully"
    else
        log_error "Failed to decrypt secrets file"
        log_info "Check your age key or regenerate secrets"
        return 1
    fi
}

# Generate Cloudflare tunnel configuration
generate_tunnel_config() {
    local config_file="$PROJECT_DIR/configs/servers/$SERVER.yml"
    local tunnel_template="$PROJECT_DIR/templates/cloudflare/tunnel-config.yml.template"
    local tunnel_dir="$PROJECT_DIR/docker/stacks/00-bifrost/config/cloudflare"
    local tunnel_config="$tunnel_dir/tunnel.yml"

    log_info "Generating Cloudflare tunnel configuration..."

    # Create tunnel config directory
    mkdir -p "$tunnel_dir"

    # Get server domain
    local domain=$(python3 -c "import yaml; config=yaml.safe_load(open('$config_file')); print(config['server']['domain'])")
    if [[ -n "$DOMAIN_OVERRIDE" ]]; then
        domain="$DOMAIN_OVERRIDE"
    fi

    # Export variables for envsubst
    export SERVER_NAME="$SERVER"
    export DOMAIN="$domain"
    export INTERNAL_DOMAIN="$SERVER.local"

    # Generate tunnel config from template
    envsubst < "$tunnel_template" > "$tunnel_config"

    log_success "Tunnel configuration created: $tunnel_config"
}

# Create required directories
create_directories() {
    local env_file="$PROJECT_DIR/docker/env/$SERVER/.env"
    
    log_info "Creating required directories..."

    # Source environment variables
    source "$env_file"

    # Create volume directories
    local dirs=(
        "$CONFIG_BASE"
        "$DATA_BASE"
        "$DOWNLOADS_BASE"
    )

    # Add media directory for NAS servers
    if [[ -n "${MEDIA_BASE:-}" ]]; then
        dirs+=("$MEDIA_BASE")
    fi

    for dir in "${dirs[@]}"; do
        if [[ "$DRY_RUN" == "false" ]]; then
            sudo mkdir -p "$dir"
            sudo chown -R "$PUID:$PGID" "$dir" 2>/dev/null || true
        fi
        log_info "Directory: $dir"
    done

    log_success "Directories created successfully"
}

# Get enabled stacks from server config
get_enabled_stacks() {
    local config_file="$PROJECT_DIR/configs/servers/$SERVER.yml"
    
    python3 << EOF
import yaml

with open('$config_file', 'r') as f:
    config = yaml.safe_load(f)

enabled_stacks = config['stacks']['enabled']
for stack in enabled_stacks:
    print(stack)
EOF
}

# Deploy specific stack
deploy_stack() {
    local stack_name="$1"
    local stack_dir="$PROJECT_DIR/docker/stacks/$stack_name"
    local env_file="$PROJECT_DIR/docker/env/$SERVER/.env"

    if [[ ! -d "$stack_dir" ]]; then
        log_error "Stack directory not found: $stack_dir"
        return 1
    fi

    if [[ ! -f "$stack_dir/docker-compose.yml" ]]; then
        log_error "Docker compose file not found: $stack_dir/docker-compose.yml"
        return 1
    fi

    log_info "Deploying stack: $stack_name"

    if [[ "$DRY_RUN" == "false" ]]; then
        cd "$stack_dir"
        docker compose --env-file "$env_file" up -d
        cd "$PROJECT_DIR"
    else
        log_info "DRY RUN: Would deploy $stack_name with env file $env_file"
    fi

    log_success "Stack $stack_name deployed successfully"
}

# Create external networks
create_networks() {
    local env_file="$PROJECT_DIR/docker/env/$SERVER/.env"
    source "$env_file"

    log_info "Creating Docker networks..."

    local networks=("${SERVER_NAME}-network" "${SERVER_NAME}-proxy")

    for network in "${networks[@]}"; do
        if [[ "$DRY_RUN" == "false" ]]; then
            # Check if network exists and has correct labels
            if docker network inspect "$network" >/dev/null 2>&1; then
                # Check if network has conflicting labels
                local has_compose_label=$(docker network inspect "$network" --format '{{index .Labels "com.docker.compose.network"}}' 2>/dev/null || echo "")
                if [[ -n "$has_compose_label" ]]; then
                    log_warning "Network $network has conflicting Docker Compose labels, recreating..."
                    # Remove conflicting network (only if no containers are using it)
                    local containers_using=$(docker network inspect "$network" --format '{{len .Containers}}' 2>/dev/null || echo "0")
                    if [[ "$containers_using" == "0" ]]; then
                        docker network rm "$network" 2>/dev/null || true
                        docker network create "$network" --driver bridge
                        log_info "Recreated network: $network"
                    else
                        log_warning "Network $network has containers attached, skipping recreation"
                        log_info "Stop containers and manually remove network if needed: docker network rm $network"
                    fi
                else
                    log_info "Network already exists: $network"
                fi
            else
                docker network create "$network" --driver bridge
                log_info "Created network: $network"
            fi
        else
            log_info "DRY RUN: Would create network $network"
        fi
    done
}

# Main deployment function
main() {
    parse_args "$@"
    
    log_info "Starting deployment for server: $SERVER"
    
    # Validate configuration
    validate_config
    
    # Generate environment and config files
    generate_env
    generate_tunnel_config
    
    # Create directories and networks
    create_directories
    create_networks
    
    # Deploy stacks
    if [[ -n "$STACK" ]]; then
        # Deploy specific stack
        deploy_stack "$STACK"
    else
        # Deploy all enabled stacks
        log_info "Deploying all enabled stacks..."
        while IFS= read -r stack; do
            deploy_stack "$stack"
        done < <(get_enabled_stacks)
    fi
    
    log_success "Deployment completed for $SERVER"
    
    # Show access information
    local domain=$(python3 -c "import yaml; config=yaml.safe_load(open('$PROJECT_DIR/configs/servers/$SERVER.yml')); print(config['server']['domain'])")
    if [[ -n "$DOMAIN_OVERRIDE" ]]; then
        domain="$DOMAIN_OVERRIDE"
    fi
    
    echo
    log_info "Access URLs:"
    echo "  Dashboard: https://home-$SERVER.$domain"
    echo "  Grafana:   https://grafana-$SERVER.$domain"
    echo "  Internal:  http://home.$SERVER.local"
    echo
}

# Run main function
main "$@"