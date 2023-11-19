#!/bin/bash
# Easy-to-use backup script with S3 and encryption options.
# Source: https://github.com/flavienbwk/backupcli

usage() {
    echo "Usage: $0 <source_path> [options]"
    echo
    echo "Arguments:"
    echo "  source_path              Path to the file or directory to be archived."
    echo
    echo "Options:"
    echo "  --name <prefix_name>      Specify a prefix name for the archive file. (Mandatory)"
    echo "  --dest <destination_dir>  Optional if s3 options provided."
    echo "                            Path to the directory where the archive will be saved."
    echo "                            If not provided, a temporary directory will be used."
    echo "  --enc <encryption_key>    Encrypt the archive with the specified encryption key."
    echo "  --s3-bucket <bucket_name> Specify the S3 bucket for backup."
    echo "  --s3-region <region_name> Specify the S3 region for the bucket."
    echo
    echo "Examples:"
    echo "  $0 /path/to/source --dst /path/to/destination --name backup"
    echo "  $0 /path/to/source --dst /path/to/destination --name backup --enc secretkey"
    echo "  $0 /path/to/source --name backup --enc secretkey --s3-bucket mybucket --s3-region us-east-1"
    exit 1
}

# Initialize variables
ENCRYPTION_KEY=""
S3_BUCKET=""
S3_REGION=""
PREFIX_NAME="archive" # Default prefix name
SOURCE_PATH=""
DEST_DIR=""

# Check if zip is installed
if ! command -v zip &> /dev/null; then
    echo "zip package is not installed. Please install it and try again."
    exit 1
fi

# Check if s3backup binary is installed
if ! command -v s3backup &> /dev/null; then
    echo "Install s3backup from https://github.com/tomcz/s3backup"
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
        --name)
            PREFIX_NAME=$2
            shift 2
            ;;
        --dest)
            DEST_DIR=$2
            shift 2
            ;;
        *)
            # Assuming the remaining argument is the source path
            if [ -z "$SOURCE_PATH" ]; then
                SOURCE_PATH=$1
            else
                usage
            fi
            shift
            ;;
    esac
done

# Verify if source path is provided and valid
if [ -z "$SOURCE_PATH" ] || [ ! -e "$SOURCE_PATH" ]; then
    echo "Invalid or no source path provided : $SOURCE_PATH"
    usage
fi

# Verify if the name is provided
if [ -z "$PREFIX_NAME" ]; then
    echo "The --name option is mandatory."
fi

# Use a temporary directory if no destination directory is provided and S3 options are not given
if [ -z "$DEST_DIR" ] && ([ -z "$S3_BUCKET" ] || [ -z "$S3_REGION" ]); then
    DEST_DIR=$(mktemp -d)
    echo "No destination directory provided. Using temporary directory: $DEST_DIR"
fi
if [ -d "$DEST_DIR" ]; then
    echo "Destination directory : $DEST_DIR"
else
    echo "Directory does not exist : $DEST_DIR"
    exit 1
fi


# Get current date and time for file naming
CURRENT_DATETIME=$(date +"%Y%m%d_%H%M%S")

# Construct the zip file name with date and time as prefix
ZIP_FILE="${CURRENT_DATETIME}_${PREFIX_NAME}.zip"

# Change to the source directory to avoid including the path in the zip file
cd "$(dirname "$SOURCE_PATH")" || exit
SOURCE_NAME="$(basename "$SOURCE_PATH")"

# Archive and compress, with optional encryption
if [ -n "$ENCRYPTION_KEY" ]; then
    zip -r -e --password "$ENCRYPTION_KEY" "$ZIP_FILE" "$SOURCE_NAME"
else
    zip -r "$ZIP_FILE" "$SOURCE_NAME"
fi

# Move the zip file to the destination directory
mv "$ZIP_FILE" "$DEST_DIR/"
DEST_PATH="$DEST_DIR/$ZIP_FILE"

echo "Archive created and moved to $DEST_DIR/$ZIP_FILE"

# Check if both S3 variables are filled
if [ -n "$S3_BUCKET" ] && [ -n "$S3_REGION" ]; then
    echo "Backing up to S3: $ZIP_FILE..."
    s3backup put --region="$S3_REGION" "$DEST_PATH" "s3://ca-bhs2-srv-01-personal-backups/$ZIP_FILE"
fi
