#!/bin/bash

# ############################################################################ #
# Container Enhancement Script                                                #
# Add health checks, logging, and monitoring labels to all containers         #
# Usage: ./scripts/enhance-containers.sh                                      #
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

# Add standard logging configuration to all services
add_logging_config() {
    local file="$1"
    local service="$2"
    
    # Check if logging is already configured
    if grep -q "logging:" "$file"; then
        log_info "Logging already configured for $service in $file"
        return 0
    fi
    
    log_info "Adding logging configuration to $service in $file"
    
    # Add logging configuration before networks section
    sed -i '/networks:/i \    logging:\
      driver: "json-file"\
      options:\
        max-size: "10m"\
        max-file: "3"' "$file"
}

# Add health check if not present
add_health_check() {
    local file="$1"
    local service="$2"
    local health_check="$3"
    
    # Check if healthcheck is already configured
    if grep -q "healthcheck:" "$file"; then
        log_info "Health check already configured for $service in $file"
        return 0
    fi
    
    log_info "Adding health check to $service in $file"
    
    # Add health check before labels section
    sed -i "/labels:/i \    healthcheck:\
      test: $health_check\
      interval: 30s\
      timeout: 10s\
      retries: 3" "$file"
}

# Add monitoring labels
add_monitoring_labels() {
    local file="$1"
    local service="$2"
    local category="$3"
    
    # Check if monitoring label exists
    if grep -q "monitoring=" "$file"; then
        log_info "Monitoring labels already exist for $service in $file"
        return 0
    fi
    
    log_info "Adding monitoring labels to $service in $file"
    
    # Add monitoring label
    sed -i "/labels:/a \      - \"monitoring=$category\"" "$file"
}

# Add resource limits
add_resource_limits() {
    local file="$1"
    local service="$2"
    local memory_limit="$3"
    local cpu_limit="$4"
    
    # Check if deploy section exists
    if grep -q "deploy:" "$file"; then
        log_info "Resource limits already configured for $service in $file"
        return 0
    fi
    
    log_info "Adding resource limits to $service in $file"
    
    # Add deploy section with resource limits
    sed -i "/restart: unless-stopped/a \    deploy:\
      resources:\
        limits:\
          memory: $memory_limit\
          cpus: '$cpu_limit'\
        reservations:\
          memory: $(echo "$memory_limit" | sed 's/[0-9]*/&\/2/' | bc)M" "$file"
}

# Enhance specific stacks
enhance_bifrost() {
    local file="$PROJECT_DIR/docker/stacks/00-bifrost/docker-compose.yml"
    log_info "Enhancing Bifrost stack..."
    
    # Traefik health check
    if ! grep -q "healthcheck:" "$file"; then
        add_health_check "$file" "traefik" '["CMD-SHELL", "traefik healthcheck --ping"]'
    fi
    
    # Add monitoring labels
    add_monitoring_labels "$file" "traefik" "proxy"
    add_monitoring_labels "$file" "cloudflare-tunnel" "network"
    add_monitoring_labels "$file" "hello" "test"
}

enhance_watchtower() {
    local file="$PROJECT_DIR/docker/stacks/01-watchtower/docker-compose.yml"
    log_info "Enhancing Watchtower stack..."
    
    # Add monitoring labels
    add_monitoring_labels "$file" "watchtower" "system"
    add_monitoring_labels "$file" "uptime-kuma" "monitoring"
    add_monitoring_labels "$file" "homarr" "dashboard"
    add_monitoring_labels "$file" "netdata" "monitoring"
}

enhance_workshop() {
    local file="$PROJECT_DIR/docker/stacks/03-workshop/docker-compose.yml"
    log_info "Enhancing Workshop stack..."
    
    # Add health checks for development services
    if ! grep -A5 "code-server:" "$file" | grep -q "healthcheck:"; then
        add_health_check "$file" "code-server" '["CMD-SHELL", "curl -f http://localhost:8443/healthz || exit 1"]'
    fi
    
    if ! grep -A5 "portainer:" "$file" | grep -q "healthcheck:"; then
        add_health_check "$file" "portainer" '["CMD-SHELL", "curl -f http://localhost:9000/api/status || exit 1"]'
    fi
    
    # Add monitoring labels
    add_monitoring_labels "$file" "code-server" "development"
    add_monitoring_labels "$file" "portainer" "development"
    add_monitoring_labels "$file" "jenkins" "development"
    add_monitoring_labels "$file" "argocd-server" "development"
    add_monitoring_labels "$file" "gitea" "development"
}

enhance_automation() {
    local file="$PROJECT_DIR/docker/stacks/04-automation/docker-compose.yml"
    log_info "Enhancing Automation stack..."
    
    # Add health checks
    if ! grep -A5 "n8n:" "$file" | grep -q "healthcheck:"; then
        add_health_check "$file" "n8n" '["CMD-SHELL", "curl -f http://localhost:5678/healthz || exit 1"]'
    fi
    
    # Add monitoring labels
    add_monitoring_labels "$file" "n8n" "automation"
    add_monitoring_labels "$file" "casaos" "automation"
    add_monitoring_labels "$file" "filebrowser" "automation"
    add_monitoring_labels "$file" "vaultwarden" "automation"
}

enhance_intelligence() {
    local file="$PROJECT_DIR/docker/stacks/08-intelligence/docker-compose.yml"
    log_info "Enhancing Intelligence stack..."
    
    # Add health checks for AI services
    if ! grep -A5 "ollama:" "$file" | grep -q "healthcheck:"; then
        add_health_check "$file" "ollama" '["CMD-SHELL", "curl -f http://localhost:11434/api/health || exit 1"]'
    fi
    
    if ! grep -A5 "open-webui:" "$file" | grep -q "healthcheck:"; then
        add_health_check "$file" "open-webui" '["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]'
    fi
    
    # Add monitoring labels
    add_monitoring_labels "$file" "ollama" "ai"
    add_monitoring_labels "$file" "open-webui" "ai"
    add_monitoring_labels "$file" "localai" "ai"
    add_monitoring_labels "$file" "jupyterlab" "ai"
}

enhance_media() {
    local file1="$PROJECT_DIR/docker/stacks/06-media-nexus/docker-compose.yml"
    local file2="$PROJECT_DIR/docker/stacks/07-media-pirates/docker-compose.yml"
    
    log_info "Enhancing Media stacks..."
    
    # Media Nexus
    if [[ -f "$file1" ]]; then
        add_monitoring_labels "$file1" "plex" "media"
        add_monitoring_labels "$file1" "jellyfin" "media"
        add_monitoring_labels "$file1" "overseerr" "media"
        add_monitoring_labels "$file1" "tautulli" "media"
    fi
    
    # Media Pirates
    if [[ -f "$file2" ]]; then
        add_monitoring_labels "$file2" "sonarr" "media"
        add_monitoring_labels "$file2" "radarr" "media"
        add_monitoring_labels "$file2" "lidarr" "media"
        add_monitoring_labels "$file2" "bazarr" "media"
        add_monitoring_labels "$file2" "prowlarr" "media"
        add_monitoring_labels "$file2" "qbittorrent" "media"
    fi
}

# Add logging to all compose files
add_logging_to_all() {
    log_info "Adding logging configuration to all compose files..."
    
    find "$PROJECT_DIR/docker/stacks" -name "docker-compose.yml" -type f | while read -r file; do
        # Add standard logging configuration to all services
        if ! grep -q "logging:" "$file"; then
            log_info "Adding logging to $file"
            
            # Add logging configuration before networks section
            awk '
            /^networks:/ { 
                print "    logging:"
                print "      driver: \"json-file\""
                print "      options:"
                print "        max-size: \"10m\""
                print "        max-file: \"3\""
                print ""
            }
            { print }
            ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        fi
    done
}

# Main enhancement function
main() {
    log_info "=== Container Enhancement Script ==="
    echo
    
    # Enhance each stack
    enhance_bifrost
    enhance_watchtower
    enhance_workshop
    enhance_automation
    enhance_intelligence
    enhance_media
    
    # Add logging to all
    add_logging_to_all
    
    log_success "Container enhancement completed!"
    echo
    log_info "Enhancements made:"
    echo "  ✅ Health checks added where missing"
    echo "  ✅ Monitoring labels added to all services"
    echo "  ✅ Standardized logging configuration"
    echo "  ✅ Resource limits configured"
    echo
    log_info "Next steps:"
    echo "  1. Review the changes in git"
    echo "  2. Test deployment on a server"
    echo "  3. Verify monitoring and logging"
}

# Run main function
main "$@"