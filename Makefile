# Makefile to install dependencies and setup backupcli.sh as backupcli

# Variables
AWSCLI_URL := https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
SEVEN_ZIP_URL := https://www.7-zip.org/a/7z2301-linux-x64.tar.xz

# Install target
install: install_7zip install_awscli install_backupcli

# Install 7-Zip
install_7zip:
	@command -v 7z >/dev/null 2>&1 || { \
		echo "Downloading and installing 7z..." && \
		temp_dir=$$(mktemp -d) && \
		curl "$(SEVEN_ZIP_URL)" -o "$$temp_dir/7z.tar.xz" && \
		tar -xf "$$temp_dir/7z.tar.xz" -C $$temp_dir && \
		sudo cp $$temp_dir/7zz /usr/local/bin/7zz && \
		sudo chmod +x /usr/local/bin/7z; \
	}

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
.PHONY: install install_7zip install_awscli install_backupcli
