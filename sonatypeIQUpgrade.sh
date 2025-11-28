#!/bin/bash
#
# Sonatype IQ Server Upgrade Script
# 
# Description: Safely upgrades Sonatype IQ Server with error handling, validation,
#              logging, and automatic rollback on failure.
#
# Usage:
#   sudo ./sonatype_iq_upgrade.sh -v 191 [options]
#
# Options:
#   -v VERSION    Version number to install (required, e.g., 191)
#   -d            Dry-run mode (simulate without making changes)
#   -k            Keep downloaded tar file after extraction
#   -s            Skip service health check (not recommended)
#   -h            Show help message
#
# Examples:
#   sudo ./sonatype_iq_upgrade.sh -v 191
#   sudo ./sonatype_iq_upgrade.sh -v 192 -d
#   sudo ./sonatype_iq_upgrade.sh -v 191 -k
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# ============================================================================
# Configuration
# ============================================================================

# Default values
VERSION=""
DRY_RUN=false
KEEP_TAR=false
SKIP_HEALTH_CHECK=false

# Paths (can be overridden with environment variables)
WORKDIR="${SONATYPE_WORKDIR:-/opt/nexus-iq-server}"
ARCHIVEDIR="${SONATYPE_ARCHIVEDIR:-/opt/nexus-iq-server/Archive}"
LOGDIR="${SONATYPE_LOGDIR:-/var/log/sonatype-upgrades}"
SERVICE_NAME="nexusiq.service"
SERVICE_USER="${SONATYPE_USER:-nexus}"
SERVICE_GROUP="${SONATYPE_GROUP:-users}"

# Download settings
DOWNLOAD_BASE_URL="https://download.sonatype.com/clm/server"
DOWNLOAD_TIMEOUT=300
MAX_RETRIES=3

# Health check settings
HEALTH_CHECK_RETRIES=30
HEALTH_CHECK_INTERVAL=10
HEALTH_CHECK_URL="${SONATYPE_HEALTH_URL:-http://localhost:8070/healthcheck}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Logging Functions
# ============================================================================

LOGFILE=""

setup_logging() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    LOGFILE="${LOGDIR}/upgrade_${VERSION}_${timestamp}.log"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$LOGDIR"
        touch "$LOGFILE"
        chmod 640 "$LOGFILE"
    fi
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOGFILE" >&2
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# ============================================================================
# Utility Functions
# ============================================================================

show_help() {
    cat << EOF
Sonatype IQ Server Upgrade Script

Usage: sudo $0 -v VERSION [options]

Required:
  -v VERSION    Version number to install (e.g., 191)

Optional:
  -d            Dry-run mode (simulate without making changes)
  -k            Keep downloaded tar file after extraction
  -s            Skip service health check (not recommended)
  -h            Show this help message

Examples:
  sudo $0 -v 191
  sudo $0 -v 192 -d
  sudo $0 -v 191 -k

Environment Variables:
  SONATYPE_WORKDIR      Working directory (default: /opt/nexus-iq-server)
  SONATYPE_ARCHIVEDIR   Archive directory (default: /opt/nexus-iq-server/Archive)
  SONATYPE_LOGDIR       Log directory (default: /var/log/sonatype-upgrades)
  SONATYPE_USER         Service user (default: nexus)
  SONATYPE_GROUP        Service group (default: users)
  SONATYPE_HEALTH_URL   Health check URL (default: http://localhost:8070/healthcheck)

EOF
    exit 0
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

validate_version() {
    if [[ -z "$VERSION" ]]; then
        log_error "Version parameter is required. Use -v to specify version."
        show_help
    fi
    
    # Validate version is numeric
    if ! [[ "$VERSION" =~ ^[0-9]+$ ]]; then
        log_error "Version must be numeric. Got: '$VERSION'"
        exit 1
    fi
    
    log_info "Version validated: $VERSION"
}

check_disk_space() {
    local required_mb=500
    local available_mb=$(df -BM "$WORKDIR" | awk 'NR==2 {print $4}' | sed 's/M//')
    
    if [[ $available_mb -lt $required_mb ]]; then
        log_error "Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB"
        exit 1
    fi
    
    log_info "Disk space check passed: ${available_mb}MB available"
}

check_dependencies() {
    local missing_deps=()
    
    for cmd in wget tar systemctl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    log_info "All required dependencies found"
}

get_current_version() {
    local jar_file=$(find "$WORKDIR" -maxdepth 1 -name "nexus-iq-server-*.jar" 2>/dev/null | head -n1)
    
    if [[ -n "$jar_file" ]]; then
        local version=$(basename "$jar_file" | grep -oP '(?<=nexus-iq-server-)[0-9.]+' | head -c 10)
        echo "$version"
    else
        echo "unknown"
    fi
}

# ============================================================================
# Service Management Functions
# ============================================================================

stop_service() {
    log_info "Stopping $SERVICE_NAME..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would stop $SERVICE_NAME"
        return 0
    fi
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        if systemctl stop "$SERVICE_NAME"; then
            log_success "Service stopped successfully"
            
            # Wait for service to fully stop
            local count=0
            while systemctl is-active --quiet "$SERVICE_NAME" && [[ $count -lt 30 ]]; do
                sleep 1
                ((count++))
            done
            
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                log_error "Service did not stop within 30 seconds"
                return 1
            fi
        else
            log_error "Failed to stop service"
            return 1
        fi
    else
        log_warning "Service was not running"
    fi
}

start_service() {
    log_info "Starting $SERVICE_NAME..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would start $SERVICE_NAME"
        return 0
    fi
    
    if systemctl start "$SERVICE_NAME"; then
        log_success "Service started successfully"
    else
        log_error "Failed to start service"
        return 1
    fi
}

check_service_health() {
    if [[ "$SKIP_HEALTH_CHECK" == "true" ]]; then
        log_warning "Skipping health check as requested"
        return 0
    fi
    
    log_info "Performing health check..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would perform health check"
        return 0
    fi
    
    local count=0
    while [[ $count -lt $HEALTH_CHECK_RETRIES ]]; do
        if curl -sf "$HEALTH_CHECK_URL" &>/dev/null; then
            log_success "Health check passed"
            return 0
        fi
        
        ((count++))
        log_info "Health check attempt $count/$HEALTH_CHECK_RETRIES..."
        sleep $HEALTH_CHECK_INTERVAL
    done
    
    log_error "Health check failed after $HEALTH_CHECK_RETRIES attempts"
    return 1
}

# ============================================================================
# Backup and Archive Functions
# ============================================================================

create_backup() {
    log_info "Creating backup of current installation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create backup in $ARCHIVEDIR"
        return 0
    fi
    
    # Create archive directory if it doesn't exist
    mkdir -p "$ARCHIVEDIR"
    
    # Find current jar files
    local jar_files=$(find "$WORKDIR" -maxdepth 1 -name "nexus-iq-server-*.jar" 2>/dev/null)
    
    if [[ -z "$jar_files" ]]; then
        log_warning "No existing jar files found to backup"
        return 0
    fi
    
    # Clean old archives (keep last 5)
    local archive_count=$(ls -1 "$ARCHIVEDIR" 2>/dev/null | wc -l)
    if [[ $archive_count -gt 5 ]]; then
        log_info "Cleaning old archives (keeping last 5)..."
        ls -1t "$ARCHIVEDIR" | tail -n +6 | xargs -I {} rm -f "$ARCHIVEDIR/{}"
    fi
    
    # Move current files to archive
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${ARCHIVEDIR}/backup_${timestamp}"
    mkdir -p "$backup_dir"
    
    while IFS= read -r file; do
        if mv "$file" "$backup_dir/"; then
            log_info "Backed up: $(basename "$file")"
        else
            log_error "Failed to backup: $(basename "$file")"
            return 1
        fi
    done <<< "$jar_files"
    
    # Store backup location for potential rollback
    echo "$backup_dir" > "${WORKDIR}/.last_backup"
    
    log_success "Backup created: $backup_dir"
}

rollback() {
    log_warning "Initiating rollback..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would perform rollback"
        return 0
    fi
    
    local backup_file="${WORKDIR}/.last_backup"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "No backup information found. Cannot rollback."
        return 1
    fi
    
    local backup_dir=$(cat "$backup_file")
    
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory not found: $backup_dir"
        return 1
    fi
    
    # Remove failed installation files
    rm -f "${WORKDIR}"/nexus-iq-server-*.jar
    
    # Restore from backup
    if mv "${backup_dir}"/* "$WORKDIR/"; then
        log_success "Files restored from backup"
        
        # Try to start service
        if start_service; then
            log_success "Rollback completed successfully"
            return 0
        else
            log_error "Failed to start service after rollback"
            return 1
        fi
    else
        log_error "Failed to restore files from backup"
        return 1
    fi
}

# ============================================================================
# Download and Installation Functions
# ============================================================================

download_release() {
    local url="${DOWNLOAD_BASE_URL}/nexus-iq-server-1.${VERSION}.0-01-bundle.tar.gz"
    local tarfile="${WORKDIR}/nexus-iq-server-1.${VERSION}.0-01-bundle.tar.gz"
    
    log_info "Downloading version ${VERSION}..."
    log_info "URL: $url"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would download from: $url"
        return 0
    fi
    
    # Remove any existing partial download
    rm -f "$tarfile"
    
    local attempt=1
    while [[ $attempt -le $MAX_RETRIES ]]; do
        log_info "Download attempt $attempt/$MAX_RETRIES..."
        
        if wget --timeout="$DOWNLOAD_TIMEOUT" \
                --tries=1 \
                --progress=dot:mega \
                -O "$tarfile" \
                "$url" 2>&1 | tee -a "$LOGFILE"; then
            
            # Verify file was downloaded and has content
            if [[ -f "$tarfile" ]] && [[ -s "$tarfile" ]]; then
                local filesize=$(stat -f%z "$tarfile" 2>/dev/null || stat -c%s "$tarfile" 2>/dev/null)
                log_success "Download completed. Size: $((filesize / 1024 / 1024))MB"
                echo "$tarfile"
                return 0
            else
                log_error "Downloaded file is empty or missing"
                rm -f "$tarfile"
            fi
        else
            # Clean up failed download
            rm -f "$tarfile"
        fi
        
        ((attempt++))
        if [[ $attempt -le $MAX_RETRIES ]]; then
            log_warning "Download failed. Retrying in 5 seconds..."
            sleep 5
        fi
    done
    
    # Ensure cleanup on final failure
    rm -f "$tarfile"
    log_error "Download failed after $MAX_RETRIES attempts"
    return 1
}

verify_download() {
    local tarfile="$1"
    
    log_info "Verifying downloaded file..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify: $tarfile"
        return 0
    fi
    
    # Check file exists
    if ! [[ -f "$tarfile" ]]; then
        log_error "Download file not found: $tarfile"
        return 1
    fi
    
    # Check file has content
    if ! [[ -s "$tarfile" ]]; then
        log_error "Download file is empty: $tarfile"
        return 1
    fi
    
    # Check minimum file size (should be at least 50MB for Sonatype IQ)
    local filesize=$(stat -f%z "$tarfile" 2>/dev/null || stat -c%s "$tarfile" 2>/dev/null)
    local min_size=$((50 * 1024 * 1024))  # 50MB in bytes
    
    if [[ $filesize -lt $min_size ]]; then
        log_error "Download file is too small (${filesize} bytes). Expected at least ${min_size} bytes."
        return 1
    fi
    
    # Verify it's a valid gzip file
    if ! gzip -t "$tarfile" 2>/dev/null; then
        log_error "Download file is not a valid gzip archive"
        return 1
    fi
    
    log_success "Download verification passed. File size: $((filesize / 1024 / 1024))MB"
    return 0
}

extract_release() {
    local tarfile="$1"
    
    log_info "Extracting release package..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would extract: $tarfile"
        return 0
    fi
    
    if ! [[ -f "$tarfile" ]]; then
        log_error "Tar file not found: $tarfile"
        return 1
    fi
    
    cd "$WORKDIR" || return 1
    
    if tar -xzf "$tarfile" --wildcards "nexus-iq-server*.jar"; then
        log_success "Extraction completed"
        
        # Verify jar file was extracted
        if ls nexus-iq-server-*.jar &>/dev/null; then
            log_info "JAR file verified"
        else
            log_error "JAR file not found after extraction"
            return 1
        fi
        
        # Remove tar file unless -k flag was used
        if [[ "$KEEP_TAR" == "false" ]]; then
            rm -f "$tarfile"
            log_info "Removed tar file"
        else
            log_info "Keeping tar file as requested"
        fi
        
        return 0
    else
        log_error "Extraction failed"
        return 1
    fi
}

set_permissions() {
    log_info "Setting file permissions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would set ownership to ${SERVICE_USER}:${SERVICE_GROUP}"
        return 0
    fi
    
    if chown "${SERVICE_USER}:${SERVICE_GROUP}" "${WORKDIR}"/nexus-iq-server-*.jar; then
        log_success "Permissions set successfully"
    else
        log_error "Failed to set permissions"
        return 1
    fi
}

verify_installation() {
    log_info "Verifying installation..."
    
    local new_version=$(get_current_version)
    
    if [[ "$new_version" == *"$VERSION"* ]]; then
        log_success "Installation verified. Version: $new_version"
        return 0
    else
        log_error "Version mismatch. Expected: $VERSION, Found: $new_version"
        return 1
    fi
}

# ============================================================================
# Main Upgrade Process
# ============================================================================

perform_upgrade() {
    local current_version=$(get_current_version)
    log_info "Current version: $current_version"
    log_info "Target version: 1.${VERSION}.0-01"
    
    # Download new version FIRST (before any system changes)
    log_info "Phase 1: Download and Validation (no system changes yet)"
    local tarfile
    if ! tarfile=$(download_release); then
        log_error "Download failed. No system changes made."
        exit 1
    fi
    
    # Verify download completed successfully
    if ! verify_download "$tarfile"; then
        log_error "Download verification failed. Removing incomplete file."
        rm -f "$tarfile"
        exit 1
    fi
    
    log_success "Download completed and verified. Proceeding with upgrade..."
    log_info "Phase 2: System Upgrade (stopping service and applying changes)"
    
    # Now that we have the file, stop service
    if ! stop_service; then
        log_error "Failed to stop service. Cleaning up download."
        rm -f "$tarfile"
        exit 1
    fi
    
    # Create backup
    if ! create_backup; then
        log_error "Backup failed. Attempting to restart service."
        start_service  # Try to restart with old version
        rm -f "$tarfile"
        exit 1
    fi
    
    # Extract new version
    if ! extract_release "$tarfile"; then
        log_error "Extraction failed. Rolling back..."
        rollback
        exit 1
    fi
    
    # Set permissions
    if ! set_permissions; then
        log_error "Failed to set permissions. Rolling back..."
        rollback
        exit 1
    fi
    
    # Verify installation
    if ! verify_installation; then
        log_error "Installation verification failed. Rolling back..."
        rollback
        exit 1
    fi
    
    # Start service
    if ! start_service; then
        log_error "Failed to start service. Rolling back..."
        rollback
        exit 1
    fi
    
    # Health check
    if ! check_service_health; then
        log_error "Health check failed. Rolling back..."
        stop_service
        rollback
        exit 1
    fi
    
    log_success "=========================================="
    log_success "Upgrade completed successfully!"
    log_success "Previous version: $current_version"
    log_success "New version: $(get_current_version)"
    log_success "Log file: $LOGFILE"
    log_success "=========================================="
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    # Parse command line arguments
    while getopts "v:dksh" opt; do
        case $opt in
            v) VERSION="$OPTARG" ;;
            d) DRY_RUN=true ;;
            k) KEEP_TAR=true ;;
            s) SKIP_HEALTH_CHECK=true ;;
            h) show_help ;;
            *) show_help ;;
        esac
    done
    
    # Pre-flight checks
    check_root
    validate_version
    check_dependencies
    check_disk_space
    
    # Setup logging
    setup_logging
    
    log_info "=========================================="
    log_info "Sonatype IQ Server Upgrade Script"
    log_info "=========================================="
    log_info "Version: $VERSION"
    log_info "Dry Run: $DRY_RUN"
    log_info "Working Directory: $WORKDIR"
    log_info "Archive Directory: $ARCHIVEDIR"
    log_info "Log File: $LOGFILE"
    log_info "=========================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi
    
    # Perform upgrade
    perform_upgrade
}

# Run main function
main "$@"