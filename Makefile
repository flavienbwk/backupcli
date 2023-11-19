# Makefile to install dependencies and setup backupcli.sh as backupcli

# Variables
S3BACKUP_URL := https://github.com/tomcz/s3backup/releases/download/v2.4.0/s3backup-linux-amd64.gz
S3BACKUP_BIN := /usr/local/bin/s3backup

# Install target
install: install_zip install_s3backup install_backupcli

# Check and install zip if not present
install_zip:
	@which zip > /dev/null || (echo "Installing zip..."; sudo apt-get install -y zip)

# Install s3backup
install_s3backup:
	@which s3backup > /dev/null || (echo "Downloading and installing s3backup..."; \
		curl -L $(S3BACKUP_URL) | gunzip > $(S3BACKUP_BIN); \
		chmod +x $(S3BACKUP_BIN))

# Install backup.sh as backupcli
install_backupcli:
	@echo "Installing backup.sh as backupcli..."
	@cp backupcli.sh /usr/local/bin/backupcli
	@chmod +x /usr/local/bin/backupcli
	@echo "backupcli installed successfully."

# Phony targets
.PHONY: install install_zip install_s3backup install_backupcli
