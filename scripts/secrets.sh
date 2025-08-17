#!/bin/bash

# ############################################################################ #
# Secrets Management Script                                                   #
# Handle encryption, decryption, and generation of secrets                    #
# Usage: ./scripts/secrets.sh <command> <server> [options]                    #
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
Usage: $0 <command> <server> [options]

Commands:
    generate <server>    Generate secrets for server
    encrypt <server>     Encrypt secrets file
    decrypt <server>     Decrypt secrets file
    edit <server>        Edit secrets (decrypt, edit, re-encrypt)
    view <server>        View decrypted secrets

Examples:
    $0 generate lugia    # Generate secrets for lugia server
    $0 decrypt lugia     # Decrypt secrets for lugia
    $0 edit snorlax      # Edit snorlax secrets
EOF
}

# Check if age is installed
check_dependencies() {
    if ! command -v age &> /dev/null; then
        log_error "age encryption tool is not installed"
        log_info "Install with: brew install age (macOS) or apt install age (Ubuntu)"
        exit 1
    fi
}

# Generate age key if it doesn't exist
setup_age_key() {
    local age_dir="$HOME/.age"
    local key_file="$age_dir/key.txt"
    local pub_file="$age_dir/key.pub"

    if [[ ! -f "$key_file" ]]; then
        log_info "Generating age encryption key..."
        mkdir -p "$age_dir"
        age-keygen -o "$key_file"
        age-keygen -y "$key_file" > "$pub_file"
        chmod 600 "$key_file"
        log_success "Age key generated: $key_file"
        log_info "Public key: $(cat "$pub_file")"
    fi
}

# Generate random secrets
generate_secrets() {
    local server="$1"
    local secrets_dir="$PROJECT_DIR/secrets"
    local secrets_file="$secrets_dir/$server.env"

    mkdir -p "$secrets_dir"

    log_info "Generating secrets for $server..."

    # Generate various secrets
    local grafana_password=$(openssl rand -base64 32)
    local authelia_jwt=$(openssl rand -base64 64)
    local authelia_session=$(openssl rand -base64 32)
    local authelia_storage=$(openssl rand -base64 32)
    local code_server_password=$(openssl rand -base64 24)
    local code_server_sudo=$(openssl rand -base64 24)
    local n8n_password=$(openssl rand -base64 24)
    local open_webui_secret=$(openssl rand -base64 32)
    local jupyter_token=$(openssl rand -hex 32)
    local pihole_password=$(openssl rand -base64 24)
    local vaultwarden_token=$(openssl rand -base64 32)
    local onlyoffice_jwt=$(openssl rand -base64 32)
    local gitea_secret=$(openssl rand -base64 32)

    cat > "$secrets_file" << EOF
# Generated secrets for $server server
# Generated on: $(date)

# Cloudflare Configuration
CLOUDFLARE_TUNNEL_TOKEN=your-tunnel-token-here
CF_API_EMAIL=your-email@example.com
CF_DNS_API_TOKEN=your-cloudflare-api-token

# Grafana
GRAFANA_ADMIN_PASSWORD=$grafana_password

# Authelia Authentication
AUTHELIA_JWT_SECRET=$authelia_jwt
AUTHELIA_SESSION_SECRET=$authelia_session
AUTHELIA_STORAGE_KEY=$authelia_storage

# Development Tools
CODE_SERVER_PASSWORD=$code_server_password
CODE_SERVER_SUDO_PASSWORD=$code_server_sudo
GITEA_SECRET_KEY=$gitea_secret

# Automation & Productivity
N8N_PASSWORD=$n8n_password
VAULTWARDEN_ADMIN_TOKEN=$vaultwarden_token
ONLYOFFICE_JWT_SECRET=$onlyoffice_jwt

# AI/LLM Services
OPEN_WEBUI_SECRET_KEY=$open_webui_secret
JUPYTER_TOKEN=$jupyter_token

# Security & DNS
PIHOLE_PASSWORD=$pihole_password

# VPN Services
TAILSCALE_AUTH_KEY=your-tailscale-auth-key

# Media Services (for NAS servers)
PLEX_CLAIM_TOKEN=your-plex-claim-token

# Server Information
SERVER_IP=your-server-ip-address
EOF

    log_success "Secrets generated: $secrets_file"
    log_warning "IMPORTANT: Edit the file to add your actual API tokens and keys!"
    log_info "Run: $0 edit $server"
}

# Encrypt secrets file
encrypt_secrets() {
    local server="$1"
    local secrets_dir="$PROJECT_DIR/secrets"
    local secrets_file="$secrets_dir/$server.env"
    local encrypted_file="$secrets_dir/$server.env.age"
    local pub_key="$HOME/.age/key.pub"

    if [[ ! -f "$secrets_file" ]]; then
        log_error "Secrets file not found: $secrets_file"
        log_info "Generate secrets first: $0 generate $server"
        exit 1
    fi

    if [[ ! -f "$pub_key" ]]; then
        log_error "Age public key not found: $pub_key"
        setup_age_key
    fi

    log_info "Encrypting secrets for $server..."
    age -r "$(cat "$pub_key")" -o "$encrypted_file" "$secrets_file"
    
    # Remove unencrypted file
    rm "$secrets_file"
    
    log_success "Secrets encrypted: $encrypted_file"
}

# Decrypt secrets file
decrypt_secrets() {
    local server="$1"
    local secrets_dir="$PROJECT_DIR/secrets"
    local secrets_file="$secrets_dir/$server.env"
    local encrypted_file="$secrets_dir/$server.env.age"
    local key_file="$HOME/.age/key.txt"

    if [[ ! -f "$encrypted_file" ]]; then
        log_error "Encrypted secrets file not found: $encrypted_file"
        exit 1
    fi

    if [[ ! -f "$key_file" ]]; then
        log_error "Age private key not found: $key_file"
        log_info "Run setup first: $0 setup"
        exit 1
    fi

    log_info "Decrypting secrets for $server..."
    age -d -i "$key_file" -o "$secrets_file" "$encrypted_file"
    
    log_success "Secrets decrypted: $secrets_file"
}

# Edit secrets (decrypt, edit, re-encrypt)
edit_secrets() {
    local server="$1"
    local secrets_dir="$PROJECT_DIR/secrets"
    local secrets_file="$secrets_dir/$server.env"

    # Decrypt first
    decrypt_secrets "$server"

    # Edit with default editor
    "${EDITOR:-nano}" "$secrets_file"

    # Re-encrypt
    encrypt_secrets "$server"

    log_success "Secrets edited and re-encrypted"
}

# View secrets (decrypt and display)
view_secrets() {
    local server="$1"
    local secrets_dir="$PROJECT_DIR/secrets"
    local secrets_file="$secrets_dir/$server.env"
    local encrypted_file="$secrets_dir/$server.env.age"
    local key_file="$HOME/.age/key.txt"

    if [[ ! -f "$encrypted_file" ]]; then
        log_error "Encrypted secrets file not found: $encrypted_file"
        exit 1
    fi

    log_info "Viewing secrets for $server..."
    age -d -i "$key_file" "$encrypted_file"
}

# Main function
main() {
    if [[ $# -lt 2 ]]; then
        usage
        exit 1
    fi

    local command="$1"
    local server="$2"

    check_dependencies
    setup_age_key

    case "$command" in
        generate)
            generate_secrets "$server"
            ;;
        encrypt)
            encrypt_secrets "$server"
            ;;
        decrypt)
            decrypt_secrets "$server"
            ;;
        edit)
            edit_secrets "$server"
            ;;
        view)
            view_secrets "$server"
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"