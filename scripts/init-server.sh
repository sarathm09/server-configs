#!/bin/bash

# ############################################################################ #
# Server Initialization Script                                                #
# Bootstrap a new server with basic security and Docker setup                 #
# Usage: ./scripts/init-server.sh                                             #
# ############################################################################ #

set -euo pipefail

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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Get server information
get_server_info() {
    log_info "Server Setup Information"
    echo
    
    read -p "Enter admin username: " ADMIN_USER
    read -p "Enter server hostname: " SERVER_HOSTNAME
    read -p "Enter timezone (e.g., Asia/Kolkata): " TIMEZONE
    
    echo
    log_info "Configuration:"
    echo "  Admin User: $ADMIN_USER"
    echo "  Hostname: $SERVER_HOSTNAME"
    echo "  Timezone: $TIMEZONE"
    echo
    
    read -p "Continue with this configuration? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Setup cancelled"
        exit 1
    fi
}

# Update system
update_system() {
    log_info "Updating system packages..."
    apt update && apt upgrade -y
    apt install -y curl wget vim git zsh ufw fail2ban \
        software-properties-common apt-transport-https \
        ca-certificates gnupg lsb-release htop neofetch \
        python3 python3-pip age
    log_success "System updated"
}

# Set hostname and timezone
configure_system() {
    log_info "Configuring system settings..."
    
    # Set hostname
    hostnamectl set-hostname "$SERVER_HOSTNAME"
    echo "127.0.1.1 $SERVER_HOSTNAME" >> /etc/hosts
    
    # Set timezone
    timedatectl set-timezone "$TIMEZONE"
    
    # Set locale
    locale-gen en_US.UTF-8
    
    log_success "System configured"
}

# Create admin user
create_admin_user() {
    log_info "Creating admin user: $ADMIN_USER"
    
    if id "$ADMIN_USER" &>/dev/null; then
        log_warning "User $ADMIN_USER already exists"
    else
        adduser --disabled-password --gecos "" "$ADMIN_USER"
        usermod -aG sudo "$ADMIN_USER"
        
        # Copy SSH keys if they exist
        if [[ -d ~/.ssh ]]; then
            mkdir -p "/home/$ADMIN_USER/.ssh"
            cp ~/.ssh/authorized_keys "/home/$ADMIN_USER/.ssh/" || true
            chown -R "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.ssh"
            chmod 700 "/home/$ADMIN_USER/.ssh"
            chmod 600 "/home/$ADMIN_USER/.ssh/authorized_keys"
        fi
        
        log_success "Admin user created"
        
        # === Disable root login ===
        log_info "Disabling root user login"
        passwd -l root
    fi
}

# Install Docker
install_docker() {
    log_info "Installing Docker..."
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    
    # Add the repository to Apt sources
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add admin user to docker group
    usermod -aG docker "$ADMIN_USER"
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
    
    log_success "Docker installed"
}

# Configure firewall
configure_firewall() {
    log_info "Configuring UFW firewall..."
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (be careful!)
    ufw allow OpenSSH
    
    # Allow HTTP/HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Allow common service ports
    ufw allow 53/tcp    # DNS
    ufw allow 53/udp    # DNS
    
    # Enable UFW
    ufw --force enable
    
    log_success "Firewall configured"
}

# Configure SSH security
configure_ssh() {
    log_info "Configuring SSH security..."
    
    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    # SSH security settings
    cat > /etc/ssh/sshd_config.d/99-server-hardening.conf << EOF
# SSH Security Configuration
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers $ADMIN_USER
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
EOF
    
    # Test SSH config
    sshd -t
    
    log_warning "SSH will be restarted with new security settings"
    log_warning "Make sure you have SSH key access before continuing!"
    
    read -p "Restart SSH service now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl restart ssh
        log_success "SSH configured and restarted"
    else
        log_warning "SSH configuration applied but not restarted"
        log_info "Restart SSH manually: sudo systemctl restart ssh"
    fi
}

# Configure fail2ban
configure_fail2ban() {
    log_info "Configuring Fail2ban..."
    
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
backend = systemd
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 3
EOF
    
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log_success "Fail2ban configured"
}

# Create project directories
create_directories() {
    log_info "Creating project directories..."
    
    # Create base directories for Docker volumes
    mkdir -p /opt/docker/{config,data}
    mkdir -p /opt/docker/downloads
    
    # Set ownership to admin user
    chown -R "$ADMIN_USER:$ADMIN_USER" /opt/docker
    
    log_success "Directories created"
}

# Install additional tools
install_tools() {
    log_info "Installing additional tools..."
    
    # Install yq for YAML processing
    wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    chmod +x /usr/local/bin/yq
    
    # Install age for encryption
    apt install -y age
    
    log_success "Additional tools installed"
}

# Final setup
final_setup() {
    log_info "Performing final setup..."
    
    # Update package database
    apt update
    
    # Clean up
    apt autoremove -y
    apt autoclean
    
    # Display system info
    echo
    log_success "Server initialization complete!"
    echo
    log_info "System Information:"
    echo "  Hostname: $(hostname)"
    echo "  OS: $(lsb_release -d | cut -f2)"
    echo "  Kernel: $(uname -r)"
    echo "  Docker: $(docker --version)"
    echo "  IP Address: $(ip route get 1 | awk '{print $7}' | head -1)"
    echo
    log_info "Next steps:"
    echo "  1. Logout and login as $ADMIN_USER"
    echo "  2. Test SSH key authentication"
    echo "  3. Clone server-configs repository"
    echo "  4. Run deployment script"
    echo
    log_warning "IMPORTANT: Verify SSH key access before closing this session!"
}

# Main function
main() {
    echo
    log_info "=== Server Initialization Script ==="
    echo
    
    check_root
    get_server_info
    update_system
    configure_system
    # create_admin_user
    install_docker
    configure_firewall
    # configure_ssh
    configure_fail2ban
    create_directories
    install_tools
    final_setup
}

# Run main function
main "$@"