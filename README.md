# Sonatype IQ Server Upgrade Script

A production-ready bash script for safely upgrading Sonatype IQ Server with comprehensive error handling, automatic rollback, validation, and logging.

## Features

- 🛡️ **Automatic Rollback** - Reverts to previous version on any failure
- 📋 **Pre-flight Checks** - Validates environment before starting
- 📝 **Comprehensive Logging** - Timestamped logs for audit trails
- 🔄 **Retry Logic** - Automatic retries for transient failures
- 💾 **Backup Management** - Maintains last 5 backups automatically
- ✅ **Health Checks** - Verifies service is healthy after upgrade
- 🧪 **Dry-run Mode** - Test upgrades without making changes
- 🔐 **Security Hardened** - Input validation and safe file operations
- 📊 **Progress Reporting** - Color-coded status messages
- ⚙️ **Configurable** - Environment variables for all settings

## Requirements

- **Operating System**: Linux with systemd
- **Privileges**: Must run as root or with sudo
- **Dependencies**: 
  - `wget` - For downloading releases
  - `tar` - For extracting archives
  - `systemctl` - For service management
  - `curl` - For health checks
- **Disk Space**: Minimum 500MB free in working directory
- **Service**: Sonatype IQ Server installed as systemd service named `nexusiq.service`

## Installation

1. **Download the script**
   ```bash
   curl -O https://your-repo/sonatype_iq_upgrade.sh
   # or
   wget https://your-repo/sonatype_iq_upgrade.sh
   ```

2. **Make it executable**
   ```bash
   chmod +x sonatype_iq_upgrade.sh
   ```

3. **Verify dependencies**
   ```bash
   ./sonatype_iq_upgrade.sh -h
   ```

## Usage

### Basic Usage

```bash
# Upgrade to version 191
sudo ./sonatype_iq_upgrade.sh -v 191
```

### Command-Line Options

| Option | Description | Required |
|--------|-------------|----------|
| `-v VERSION` | Version number to install (e.g., 191) | Yes |
| `-d` | Dry-run mode (simulate without changes) | No |
| `-k` | Keep tar file after extraction | No |
| `-s` | Skip health check (not recommended) | No |
| `-h` | Show help message | No |

### Examples

**Standard upgrade:**
```bash
sudo ./sonatype_iq_upgrade.sh -v 191
```

**Test upgrade without making changes:**
```bash
sudo ./sonatype_iq_upgrade.sh -v 191 -d
```

**Keep downloaded tar file:**
```bash
sudo ./sonatype_iq_upgrade.sh -v 191 -k
```

**Skip health check (use with caution):**
```bash
sudo ./sonatype_iq_upgrade.sh -v 191 -s
```

**Use custom paths:**
```bash
SONATYPE_WORKDIR=/custom/path \
SONATYPE_HEALTH_URL=http://localhost:8070/healthcheck \
sudo ./sonatype_iq_upgrade.sh -v 191
```

## Configuration

### Environment Variables

All paths and settings can be customized via environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `SONATYPE_WORKDIR` | Installation directory | `/opt/nexus-iq-server` |
| `SONATYPE_ARCHIVEDIR` | Backup directory | `/opt/nexus-iq-server/Archive` |
| `SONATYPE_LOGDIR` | Log file directory | `/var/log/sonatype-upgrades` |
| `SONATYPE_USER` | Service user | `nexus` |
| `SONATYPE_GROUP` | Service group | `users` |
| `SONATYPE_HEALTH_URL` | Health check endpoint | `http://localhost:8070/healthcheck` |

### Example with Custom Configuration

```bash
# Create environment file
cat > /etc/sonatype-upgrade.conf << 'EOF'
export SONATYPE_WORKDIR=/opt/sonatype-iq
export SONATYPE_ARCHIVEDIR=/backup/sonatype
export SONATYPE_LOGDIR=/var/log/sonatype
export SONATYPE_USER=sonatype
export SONATYPE_GROUP=sonatype
export SONATYPE_HEALTH_URL=http://localhost:8070/healthcheck
EOF

# Use configuration
source /etc/sonatype-upgrade.conf
sudo -E ./sonatype_iq_upgrade.sh -v 191
```

## How It Works

### Upgrade Process Flow

1. **Pre-flight Checks**
   - Verify running as root
   - Validate version number format
   - Check required dependencies (wget, tar, systemctl, curl)
   - Verify minimum disk space (500MB)
   - Detect current installed version

2. **Download**
   - Download new version from Sonatype
   - Retry up to 3 times on failure
   - Verify downloaded file exists and has content
   - Display download progress
   
3. **Service Shutdown**
   - Stop `nexusiq.service`
   - Wait up to 30 seconds for graceful shutdown
   - Verify service has fully stopped

4. **Backup Creation**
   - Create timestamped backup directory
   - Move current JAR files to backup
   - Clean old backups (keep last 5)
   - Record backup location for potential rollback

5. **Extraction**
   - Extract JAR file from tar archive
   - Verify JAR file was extracted successfully
   - Remove tar file (unless `-k` flag used)

6. **Installation**
   - Set correct file ownership and permissions
   - Verify version number matches expected

7. **Service Startup**
   - Start `nexusiq.service`
   - Wait for service to become active

8. **Health Check**
   - Poll health check endpoint
   - Retry up to 30 times with 10-second intervals
   - Verify service is responding correctly

9. **Completion**
   - Display success message with version info
   - Show log file location

### On Failure: Automatic Rollback

If any step fails, the script automatically:
1. Stops the service (if running)
2. Removes failed installation files
3. Restores files from backup
4. Restarts service with previous version
5. Logs the failure with details

## Logging

### Log Files

Logs are stored in `/var/log/sonatype-upgrades/` (customizable):

```
/var/log/sonatype-upgrades/
├── upgrade_191_20241128_143022.log
├── upgrade_191_20241128_150315.log
└── upgrade_192_20241129_092145.log
```

### Log File Format

```
2024-11-28 14:30:22 [INFO] Starting upgrade to version 191
2024-11-28 14:30:23 [INFO] Current version: 1.190.0-01
2024-11-28 14:30:24 [SUCCESS] Service stopped successfully
2024-11-28 14:30:25 [SUCCESS] Backup created: /opt/nexus-iq-server/Archive/backup_20241128_143024
...
```

### View Logs

```bash
# View latest log
tail -f /var/log/sonatype-upgrades/upgrade_*.log

# View all logs
ls -lt /var/log/sonatype-upgrades/

# Search for errors
grep ERROR /var/log/sonatype-upgrades/upgrade_191_*.log
```

## Backup Management

### Backup Location

Backups are stored in timestamped directories:
```
/opt/nexus-iq-server/Archive/
├── backup_20241125_120000/
├── backup_20241126_120000/
├── backup_20241127_120000/
├── backup_20241128_120000/
└── backup_20241129_120000/
```

### Automatic Cleanup

- Script automatically keeps the **last 5 backups**
- Older backups are removed during each upgrade
- Manual backups are not affected

### Manual Rollback

If you need to manually rollback:

```bash
# Stop service
sudo systemctl stop nexusiq.service

# Remove current version
sudo rm /opt/nexus-iq-server/nexus-iq-server-*.jar

# Restore from backup
sudo cp /opt/nexus-iq-server/Archive/backup_TIMESTAMP/* /opt/nexus-iq-server/

# Start service
sudo systemctl start nexusiq.service
```

## Troubleshooting

### Upgrade Fails with "Permission Denied"

**Problem:** Script cannot write to directories or modify files.

**Solution:**
```bash
# Ensure you're running as root
sudo ./sonatype_iq_upgrade.sh -v 191

# Check directory permissions
ls -ld /opt/nexus-iq-server
ls -ld /var/log/sonatype-upgrades
```

### Health Check Always Fails

**Problem:** Service is running but health check endpoint is unreachable.

**Solutions:**
1. **Verify health check URL:**
   ```bash
   curl http://localhost:8070/healthcheck
   ```

2. **Check service logs:**
   ```bash
   journalctl -u nexusiq.service -n 50
   ```

3. **Customize health check URL:**
   ```bash
   SONATYPE_HEALTH_URL=http://your-custom-url/health \
   sudo ./sonatype_iq_upgrade.sh -v 191
   ```

4. **Skip health check (temporary workaround):**
   ```bash
   sudo ./sonatype_iq_upgrade.sh -v 191 -s
   ```

### Download Fails

**Problem:** Cannot download release from Sonatype.

**Solutions:**
1. **Check internet connectivity:**
   ```bash
   ping download.sonatype.com
   ```

2. **Test download URL manually:**
   ```bash
   wget https://download.sonatype.com/clm/server/nexus-iq-server-1.191.0-01-bundle.tar.gz
   ```

3. **Check proxy settings:**
   ```bash
   echo $http_proxy
   echo $https_proxy
   ```

4. **Use proxy if needed:**
   ```bash
   export http_proxy=http://proxy.company.com:8080
   export https_proxy=http://proxy.company.com:8080
   sudo -E ./sonatype_iq_upgrade.sh -v 191
   ```

### Insufficient Disk Space

**Problem:** Not enough space for download and extraction.

**Solution:**
```bash
# Check available space
df -h /opt/nexus-iq-server

# Clean old backups manually if needed
sudo rm -rf /opt/nexus-iq-server/Archive/backup_OLD_TIMESTAMP

# Or change archive location to larger disk
SONATYPE_ARCHIVEDIR=/large-disk/sonatype-backups \
sudo ./sonatype_iq_upgrade.sh -v 191
```

### Service Won't Start After Upgrade

**Problem:** Service fails to start with new version.

**What the script does automatically:**
- Detects startup failure
- Rolls back to previous version
- Restarts with old version
- Logs the error

**Manual investigation:**
```bash
# Check service status
sudo systemctl status nexusiq.service

# View recent logs
sudo journalctl -u nexusiq.service -n 100

# Check configuration
sudo cat /etc/sonatype-iq-server/config.yml
```

### Version Number Format Issues

**Problem:** "Version must be numeric" error.

**Solution:**
```bash
# Correct format (just the middle number)
sudo ./sonatype_iq_upgrade.sh -v 191    # ✅ Correct

# Incorrect formats
sudo ./sonatype_iq_upgrade.sh -v 1.191.0-01  # ❌ Wrong
sudo ./sonatype_iq_upgrade.sh -v latest      # ❌ Wrong
```

The script expects just the version number (e.g., `191`), which it expands to `1.191.0-01` internally.

## Dry-run Mode

Dry-run mode allows you to test the upgrade process without making any actual changes.

### Using Dry-run

```bash
sudo ./sonatype_iq_upgrade.sh -v 191 -d
```

### What Dry-run Does

✅ **Performs:**
- All validation checks
- Version detection
- Disk space verification
- Dependency checks
- Logs all operations

❌ **Skips:**
- Service stop/start
- File downloads
- File modifications
- Backup creation
- Actual installation

### Example Output

```
[DRY RUN] Would stop nexusiq.service
[DRY RUN] Would create backup in /opt/nexus-iq-server/Archive
[DRY RUN] Would download from: https://download.sonatype.com/clm/server/...
[DRY RUN] Would extract: /opt/nexus-iq-server/nexus-iq-server-1.191.0-01-bundle.tar.gz
[DRY RUN] Would set ownership to nexus:users
[DRY RUN] Would start nexusiq.service
[DRY RUN] Would perform health check
```

## Security Considerations

### Running as Root

This script requires root privileges because it:
- Manages systemd services
- Modifies files in system directories
- Changes file ownership

**Best practice:** Use `sudo` rather than logging in as root:
```bash
sudo ./sonatype_iq_upgrade.sh -v 191
```

### Input Validation

The script validates:
- ✅ Version number is numeric only
- ✅ Required parameters are provided
- ✅ File paths exist and are accessible
- ✅ Downloaded files have content

### Safe File Operations

- All variables are properly quoted
- Uses `${VAR:?}` to prevent unset variable expansion
- Verifies operations before proceeding
- Creates backups before modifications

### Download Security

- Uses HTTPS for all downloads
- Verifies file size after download
- Checks file existence before extraction
- Multiple retry attempts for reliability

## Integration Examples

### Scheduled Upgrades

```bash
# Create upgrade script
cat > /usr/local/bin/scheduled-sonatype-upgrade.sh << 'EOF'
#!/bin/bash
# Upgrade to latest version on schedule
VERSION=191
/opt/scripts/sonatype_iq_upgrade.sh -v $VERSION 2>&1 | \
    tee /var/log/sonatype-upgrades/scheduled_$(date +%Y%m%d).log

# Send notification (optional)
if [ $? -eq 0 ]; then
    echo "Sonatype IQ Server upgraded to $VERSION successfully" | \
        mail -s "Sonatype Upgrade Success" admin@company.com
else
    echo "Sonatype IQ Server upgrade to $VERSION failed. Check logs." | \
        mail -s "Sonatype Upgrade FAILED" admin@company.com
fi
EOF

chmod +x /usr/local/bin/scheduled-sonatype-upgrade.sh
```

### Notification Integration

```bash
# With Slack notification
sudo ./sonatype_iq_upgrade.sh -v 191 && \
    curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"✅ Sonatype IQ upgraded to 191"}' \
    $SLACK_WEBHOOK_URL

# With email notification
sudo ./sonatype_iq_upgrade.sh -v 191 && \
    echo "Upgrade completed successfully" | \
    mail -s "Sonatype Upgrade Complete" admin@company.com
```

### CI/CD Pipeline Integration

```yaml
# GitLab CI example
sonatype-upgrade:
  stage: deploy
  script:
    - scp sonatype_iq_upgrade.sh server:/tmp/
    - ssh server "sudo /tmp/sonatype_iq_upgrade.sh -v ${VERSION}"
  only:
    - schedules
  variables:
    VERSION: "191"
```

## Version Compatibility

### Sonatype IQ Server Versions

This script is compatible with Sonatype IQ Server versions that follow the naming convention:
```
nexus-iq-server-1.XXX.0-01-bundle.tar.gz
```

Where `XXX` is the version number (e.g., 191, 192, 193).

### Tested Versions

- ✅ Sonatype IQ Server 1.180.x - 1.195.x
- ✅ RHEL/CentOS 7, 8, 9
- ✅ Ubuntu 20.04, 22.04
- ✅ Debian 10, 11, 12

### Known Limitations

- Does not support Windows
- Requires systemd (not compatible with SysV init)
- Assumes service name is `nexusiq.service`
- Download URL format must match Sonatype's current pattern

## Best Practices

### Before Upgrading

1. **Review release notes** - Check Sonatype's release notes for breaking changes
2. **Test in non-production** - Always test upgrades in dev/staging first
3. **Schedule maintenance window** - Notify users of downtime
4. **Verify backups** - Ensure backup system is working
5. **Document current state** - Note current version and configuration

### During Upgrade

1. **Use dry-run first** - Test with `-d` flag before actual upgrade
2. **Monitor logs** - Watch log file during upgrade
3. **Stay available** - Be ready to investigate issues
4. **Keep terminal open** - Don't close session during upgrade

### After Upgrade

1. **Verify functionality** - Test key features
2. **Check logs** - Review both script logs and application logs
3. **Monitor performance** - Watch system resources
4. **Document completion** - Record new version and any issues
5. **Keep backup** - Don't delete backup until verified stable

### Rollback Planning

Always have a rollback plan:
1. Script performs automatic rollback on failure
2. Manual rollback procedure documented above
3. Keep database backups separate
4. Test rollback procedure in non-production
5. Know recovery time objectives (RTO)

## FAQ

**Q: Can I upgrade multiple versions at once (e.g., 190 → 193)?**  
A: Yes, the script handles this. However, review release notes for any breaking changes between versions.

**Q: What happens if the download is interrupted?**  
A: The script will retry up to 3 times. If all retries fail, it will abort and leave the system in its original state (no changes made).

**Q: Can I run this script remotely via SSH?**  
A: Yes, but ensure you use `nohup` or `screen`/`tmux` to prevent interruption if connection drops:
```bash
nohup sudo ./sonatype_iq_upgrade.sh -v 191 > upgrade.log 2>&1 &
```

**Q: How do I upgrade if my server has no internet access?**  
A: Download the tar file manually, place it in `SONATYPE_WORKDIR`, modify the script to skip download step, or use a proxy.

**Q: Does this script update configuration files?**  
A: No, the script only upgrades the JAR file. Configuration files are not modified. Always review configuration changes in release notes.

**Q: Can I schedule automatic upgrades?**  
A: While possible, it's not recommended without human oversight. Use scheduled checks for new versions (see version checker scripts), then manually approve upgrades.

**Q: What if health check URL is different?**  
A: Set the `SONATYPE_HEALTH_URL` environment variable to your health check endpoint.

**Q: How long does an upgrade take?**  
A: Typically 5-10 minutes, depending on download speed and service startup time.

## Support

For issues, questions, or feature requests:
- Open an issue on GitHub
- Contact: [your-contact-info]
- Review logs in `/var/log/sonatype-upgrades/`

## Related Tools

- [Sonatype IQ Version Checker](../sonatype-version-checker/) - Automated version monitoring
- [NGINX Upgrade Script](../nginx-upgrade/) - Similar upgrade automation for NGINX
- [Elasticsearch Upgrade Script](../elasticsearch-upgrade/) - Elasticsearch upgrade automation

## License

[Specify your license here]

## Changelog

### Version 1.0
- Initial release with production-ready features
- Automatic rollback on failure
- Comprehensive logging
- Health check integration
- Backup management
- Dry-run mode
- Pre-flight validation
- Retry logic for downloads
- Color-coded output
- Environment variable configuration

## Contributing

Contributions are welcome! Please:
1. Test thoroughly in non-production environments
2. Maintain backward compatibility
3. Add tests for new features
4. Update documentation
5. Follow existing code style

## Acknowledgments

- Sonatype team for Nexus IQ Server
- DevOps community for best practices
- Contributors and testers