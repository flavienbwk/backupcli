# Makefile to install dependencies and setup backupcli.sh as backupcli

# Variables
AWSCLI_URL := https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip

# Install target
install: install_zip install_awscli install_backupcli

# Check and install zip if not present
install_zip:
	@which zip > /dev/null || (echo "Installing zip..."; sudo apt-get install -y zip)

# Install AWS cli
install_awscli:
	@command -v aws >/dev/null 2>&1 || { \
		echo "Downloading and installing AWS CLI..." && \
		temp_dir=$$(mktemp -d) && \
		curl "$(AWSCLI_URL)" -o "$$temp_dir/awscliv2.zip" && \
		unzip "$$temp_dir/awscliv2.zip" -d $$temp_dir && \
		sudo $$temp_dir/aws/install; \
	}

# Install backup.sh as backupcli
install_backupcli:
	@echo "Installing backup.sh as backupcli..."
	@cp backupcli.sh /usr/local/bin/backupcli
	@chmod +x /usr/local/bin/backupcli
	@echo "backupcli installed successfully."

# Phony targets
.PHONY: install install_zip install_awscli install_backupcli
