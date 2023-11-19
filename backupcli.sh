#!/bin/bash
# Easy-to-use backup script with S3 and encryption options.
# Source: https://github.com/flavienbwk/backupcli
set -e

BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}$(date --iso-8601=seconds) INFO:${NC} $1"
}

log_error() {
    echo -e "${RED}$(date --iso-8601=seconds) ERROR:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}$(date --iso-8601=seconds) WARN:${NC} $1"
}

usage() {
    echo "Usage: $0 [options] <source_paths, ...>"
    echo
    echo "Arguments:"
    echo "  source_paths              Path to the file or directory to be archived."
    echo "                            Glob patterns supported."
    echo
    echo "Options:"
    echo "  --name <prefix_name>      Specify a prefix name for the archive file."
    echo "  --dest <destination_dir>  Path to the directory where the archive will be saved."
    echo "                            If not provided, a temporary directory will be used."
    echo "                            Might be use omitted for dry-run."
    echo "  --enc <encryption_key>    Encrypt the archive with the specified encryption key."
    echo "  --s3-bucket <bucket_name> Specify the S3 bucket for backup."
    echo "  --s3-region <region_name> Specify the S3 region for the bucket."
    echo "  --s3-storage-class <sc>   Specify the S3 storage class for the bucket."
    echo "                            Default to STANDARD. Can be INTELLIGENT_TIERING, STANDARD_IA, GLACIER..."
    echo
    echo "Examples:"
    echo "  $0 /path/to/source --dst /path/to/destination"
    echo "  $0 /path/to/source --dst /path/to/destination --name backup --enc secretkey"
    echo "  $0 /path/to/source --name backup --enc secretkey --s3-bucket mybucket --s3-region us-east-1"
}

# Function to output the size of the provided file
get_file_size() {
    local zip_file="$1"
    local size
    size=$(du -h "$zip_file" | cut -f1)
    echo "$size"
}

# Initialize variables defaults
ENCRYPTION_KEY=""
S3_BUCKET=""
S3_REGION=""
S3_STORAGE_CLASS="STANDARD"
PREFIX_NAME="archive"
SOURCE_PATHS=()
DEST_DIR=""

# Check if zip is installed
if ! command -v zip &> /dev/null; then
    log_error "zip package is not installed. Please install it and try again."
    exit 1
fi

# Check if s3backup binary is installed
if ! command -v s3backup &> /dev/null; then
    log_error "Install s3backup from https://github.com/tomcz/s3backup or run 'make install'"
    exit 1
fi

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --enc)
            ENCRYPTION_KEY=$2
            shift 2
            ;;
        --s3-bucket)
            S3_BUCKET=$2
            shift 2
            ;;
        --s3-region)
            S3_REGION=$2
            shift 2
            ;;
        --s3-storage-class)
            S3_STORAGE_CLASS=$2
            shift 2
            ;;
        --name)
            PREFIX_NAME=$2
            shift 2
            ;;
        --dest)
            DEST_DIR=$2
            shift 2
            ;;
        *)
            # Assuming the remaining arguments are the sources paths
            SOURCE_PATHS+=("$1")
            shift
            ;;
    esac
done

if [ ${#SOURCE_PATHS[@]} -eq 0 ]; then
    usage
    exit 1
fi

# Verify if at least one source path is provided and valid
if [ ${#SOURCE_PATHS[@]} -eq 0 ]; then
    usage
    log_error "No source path provided."
fi

# Verify if at least one source path is provided and valid
VALID_SOURCE_PATHS=()
for SOURCE in "${SOURCE_PATHS[@]}"; do
    if [ -f "$SOURCE" ] || [ -d "$SOURCE" ]; then
        VALID_SOURCE_PATHS+=("$SOURCE")
    else
        log_warning "File not found: $SOURCE. Skipping."
    fi
done
if [ ${#VALID_SOURCE_PATHS[@]} -eq 0 ]; then
    log_error "No valid path provided."
    exit 1
fi

# Assess valid S3 options
if [ -n "$S3_BUCKET" ] || [ -n "$S3_REGION" ]; then
    if [ -z "$S3_BUCKET" ] || [ -z "$S3_REGION" ]; then
        log_error "You must specify both --s3-bucket and --s3-region options to use S3."
        exit 1
    fi
else
    if [ -z "$DEST_DIR" ]; then
        log_warning "Dry-run mode : you're not specifying S3 options nor a --dest path."
    fi
fi

# Use a temporary directory if no destination directory is provided
if [ -z "$DEST_DIR" ]; then
    DEST_DIR=$(mktemp -d)
    log_info "No destination directory provided. Using temporary directory: $DEST_DIR"
fi
if [ -d "$DEST_DIR" ]; then
    log_info "Destination directory : $DEST_DIR"
else
    log_info "Directory does not exist : $DEST_DIR"
    exit 1
fi


# Get current date and time for file naming
CURRENT_DATETIME=$(date +"%Y%m%d_%H%M%S")

# Construct the zip file name with date and time as prefix
ZIP_FILE="${CURRENT_DATETIME}_${PREFIX_NAME}.tar.gz"
if [ -n "${ENCRYPTION_KEY}" ]; then
    ZIP_FILE="$ZIP_FILE.gpg"
fi
ZIP_FILE_PATH="${DEST_DIR}/${ZIP_FILE}"

# Calculate total size of VALID_SOURCE_PATHS
TOTAL_SIZE=0
for SOURCE in "${VALID_SOURCE_PATHS[@]}"; do
    if [ -d "$SOURCE" ]; then
        SIZE=$(du -sb "$SOURCE" | cut -f1)
    else
        SIZE=$(stat -c%s "$SOURCE")
    fi
    TOTAL_SIZE=$((TOTAL_SIZE + SIZE + 4096))
done

# Get available disk space in DEST_DIR
AVAILABLE_SPACE=$(( $(df --output=avail "$DEST_DIR" | tail -n 1) * 1000))

# Convert sizes to human-readable format
TOTAL_SIZE_HR=$(numfmt --to=iec --suffix=B "$TOTAL_SIZE")
AVAILABLE_SPACE_HR=$(numfmt --to=iec --suffix=B "$AVAILABLE_SPACE")

# Check if there is enough space
if [ "$TOTAL_SIZE" -gt "$AVAILABLE_SPACE" ]; then
    log_error "Not enough space in destination directory $DEST_DIR ($TOTAL_SIZE_HR requested but only $AVAILABLE_SPACE_HR are available)."
    exit 1
fi

# Archive and compress, with optional encryption
log_info "${#VALID_SOURCE_PATHS[@]} files will be zipped (maximum $TOTAL_SIZE_HR)..."
for SOURCE in "${VALID_SOURCE_PATHS[@]}"; do
    if [ -n "$ENCRYPTION_KEY" ]; then
        # Encrypt the archive with a password
        tar -czf - --exclude='*.sock' "$SOURCE" | gpg --symmetric --batch --yes --passphrase "$ENCRYPTION_KEY" -o "$ZIP_FILE_PATH"
    else
        # Create a regular, non-encrypted compressed archive
        tar -czf "$ZIP_FILE_PATH" --exclude='*.sock' "$SOURCE"
    fi
done

ZIP_FILE_SIZE=$(get_file_size "$ZIP_FILE_PATH")
log_info "Archive complete ($ZIP_FILE_SIZE): $ZIP_FILE_PATH"

# Check if both S3 variables are filled
if [ -n "$S3_BUCKET" ] && [ -n "$S3_REGION" ]; then
    echo "Starting S3 process for $ZIP_FILE..."
    aws s3 cp --region="$S3_REGION" --storage-class="$S3_STORAGE_CLASS" "$ZIP_FILE_PATH" "s3://$S3_BUCKET/$ZIP_FILE"
fi

log_info "End of script."
