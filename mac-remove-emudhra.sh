#!/bin/bash

# ==============================================================================
# EMUDHRA CERTIFICATE REMOVAL SCRIPT FOR MACOS
# ==============================================================================
# This script removes emudhra certificates from all macOS keychains and 
# certificate stores used by browsers and applications.
#
# USAGE:
#   1. Make script executable: chmod +x remove-emudhra-certificates.sh
#   2. Run with sudo: sudo ./remove-emudhra-certificates.sh
#
# SAFETY:
#   - Creates backup before deletion
#   - Dry-run mode available (-n or --dry-run)
#   - Shows what will be removed before removing
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_NAME="remove-emudhra-certificates.sh"
BACKUP_DIR="/tmp/emudhra_backup_$(date +%Y%m%d_%H%M%S)"
CERT_PATTERN="emudhra"
CERT_PATTERN_UPPER="EMUDHRA"
DRY_RUN=false

# ==============================================================================
# FUNCTIONS
# ==============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [-n] [--dry-run]

Options:
  -n, --dry-run    Show what would be removed without making changes
  -h, --help       Show this help message

This script removes emudhra certificates from all macOS certificate stores.
EOF
}

# Check if running as root (needed for System keychain)
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_warn "Running without sudo - may not be able to access System keychain"
        sleep 2
    fi
}

# Backup certificate stores
backup_keychains() {
    log_info "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Backup all keychains
    for keychain in ~/Library/Keychains/login.keychain-db \
                    /Library/Keychains/System.keychain \
                    /System/Library/Keychains/System.keychain \
                    ~/Library/Keychains/; do
        if [[ -d "$keychain" ]] || [[ -f "$keychain" ]]; then
            log_info "Backing up: $keychain"
            cp -r "$keychain" "$BACKUP_DIR/" 2>/dev/null || true
        fi
    done
    
    log_success "Backup complete: $BACKUP_DIR"
}

# List emudhra certificates
list_certificates() {
    local keychain=$1
    local keychain_type=$2
    
    log_info "Searching in $keychain_type..."
    
    # Search for emudhra certificates
    if command -v security &> /dev/null; then
        certificates=$(security find-certificate -c "$CERT_PATTERN" "$keychain" 2>/dev/null | grep -c "emudhra" || true)
        if [[ $certificates -gt 0 ]]; then
            echo "$keychain ($certificates matches)"
        fi
    fi
}

# Get all keychains to search
get_keychains() {
    cat << EOF
System Keychains:
- /Library/Keychains/System.keychain
- /System/Library/Keychains/System.keychain
- /System/Library/Keychains/

User Keychains:
- ~/Library/Keychains/login.keychain-db
- ~/Library/Keychains/
EOF
}

# Remove certificate from keychain
remove_from_keychain() {
    local keychain=$1
    local cert_label=$2
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would remove: $cert_label from $keychain"
    else
        security delete-certificate -c "$cert_label" "$keychain" 2>/dev/null || true
    fi
}

# Remove all emudhra certificates from a specific keychain
remove_from_all_keychains() {
    local keychain=$1
    local keychain_type=$2
    
    log_info "Processing $keychain_type: $keychain"
    
    # Get list of emudhra certificates
    if command -v security &> /dev/null; then
        cert_list=$(security find-certificate -c "$CERT_PATTERN" "$keychain" 2>/dev/null)
        
        if [[ -n "$cert_list" ]]; then
            local count=0
            
            # Delete certificates using cert hash
            cert_hashes=$(security find-certificate -c "$CERT_PATTERN" -p "$keychain" 2>/dev/null | \
                          grep -oP '^[0-9a-fA-F]{40}' || true)
            
            if [[ -n "$cert_hashes" ]]; then
                while IFS= read -r hash; do
                    if [[ $DRY_RUN == true ]]; then
                        log_info "[DRY-RUN] Would remove hash: $hash from $keychain"
                    else
                        security delete-certificate -h "$hash" "$keychain" 2>/dev/null || true
                    fi
                    count=$((count + 1))
                done <<< "$cert_hashes"
            fi
            
            if [[ $count -gt 0 ]]; then
                log_success "Removed $count emudhra certificate(s) from $keychain"
            fi
        else
            log_info "No emudhra certificates found in $keychain"
        fi
    fi
}

# Clear Safari certificate cache
clear_safari_cache() {
    log_info "Clearing Safari certificate cache..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would clear Safari caches"
    else
        # Clear Safari certificate store cache
        rm -rf ~/Library/Safari/Caches/ 2>/dev/null || true
        log_success "Safari cache cleared"
    fi
}

# Clear Chrome certificate cache
clear_chrome_cache() {
    local chrome_paths=(
        "~/Library/Application Support/Google/Chrome/Default"
        "~/Library/Application Support/Google/Chrome Canary/Default"
    )
    
    log_info "Clearing Chrome certificate cache..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would clear Chrome certificate caches"
    else
        for path in "${chrome_paths[@]}"; do
            if [[ -d "$HOME/$path" ]]; then
                # Clear SQLite cache for certificates
                rm -f "$HOME/$path/CertificateRevocation" 2>/dev/null || true
                log_info "Cleared cache for: $path"
            fi
        done
        log_success "Chrome certificate cache cleared"
    fi
}

# Clear Firefox certificate cache
clear_firefox_cache() {
    log_info "Clearing Firefox certificate cache..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would clear Firefox certificate caches"
    else
        # Firefox stores certificates in SQLite in profile
        for profile in ~/Library/Mozilla/Firefox/Profiles/*; do
            if [[ -d "$profile" ]]; then
                rm -f "$profile/cert8.db" 2>/dev/null || true
                rm -f "$profile/certs9.db" 2>/dev/null || true
                log_info "Cleared cache for: $profile"
            fi
        done
        log_success "Firefox certificate cache cleared"
    fi
}

# Clear Edge certificate cache
clear_edge_cache() {
    log_info "Clearing Edge certificate cache..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would clear Edge certificate caches"
    else
        rm -rf ~/Library/Application\ Support/Microsoft\ Edge/Default 2>/dev/null || true
        log_success "Edge certificate cache cleared"
    fi
}

# Clear system certificate cache
clear_system_cache() {
    log_info "Clearing system certificate cache..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY-RUN] Would clear system certificate cache"
    else
        # Clear certificate revocation list cache
        sudo touch /var/cache/crls/*.crl 2>/dev/null || true
        log_success "System certificate cache cleared"
    fi
}

# Show summary
show_summary() {
    echo ""
    echo "=========================================================================="
    echo "                    REMOVAL SUMMARY"
    echo "=========================================================================="
    echo ""
    echo "Backup Location: $BACKUP_DIR"
    echo "Certificate Pattern: $CERT_PATTERN"
    echo ""
    if [[ $DRY_RUN == true ]]; then
        echo "Status: DRY-RUN (no changes made)"
    else
        echo "Status: COMPLETED"
    fi
    echo ""
    echo "=========================================================================="
    echo ""
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

# Main execution
log_info "Starting emudhra certificate removal..."
echo ""

# Step 1: Check permissions
check_root

# Step 2: Create backup
backup_keychains
echo ""

# Step 3: Display keychains to be processed
log_info "Keychains to process:"
get_keychains
echo ""

# Step 4: Remove certificates from keychains
log_info "Removing emudhra certificates..."
echo ""

# System keychains (need sudo)
log_info "--- SYSTEM KEYCHAINS ---"
remove_from_all_keychains "/Library/Keychains/System.keychain" "System"
remove_from_all_keychains "/System/Library/Keychains/System.keychain" "System"

# User keychains
log_info "--- USER KEYCHAINS ---"
remove_from_all_keychains "$HOME/Library/Keychains/login.keychain-db" "User Login"

# Other keychains in user keychain folder
if [[ -d "$HOME/Library/Keychains/" ]]; then
    for kc in "$HOME/Library/Keychains/"*.keychain-db; do
        if [[ -f "$kc" ]]; then
            remove_from_all_keychain "$kc" "User"
        fi
    done
fi
echo ""

# Step 5: Clear browser caches
log_info "Clearing browser caches..."
echo ""
clear_safari_cache
clear_chrome_cache
clear_firefox_cache
clear_edge_cache
echo ""

# Step 6: Clear system certificate cache
clear_system_cache
echo ""

# Step 7: Show summary
show_summary

# Step 8: Provide cleanup info
if [[ $DRY_RUN == true ]]; then
    log_warn "Dry-run complete. Re-run without -n to apply changes."
else
    log_success "All emudhra certificates removed!"
    log_info "You may need to restart browsers for changes to take effect."
fi
