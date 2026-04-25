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
    echo "  --name <prefix_name>                Specify a prefix name for the archive file."
    echo "  --dest <destination_dir>            Path to the directory where the archive will be saved."
    echo "                                      If not provided, a temporary directory will be used."
    echo "                                      Might be use omitted for dry-run."
    echo "  --enc <encryption_key>              Encrypt the archive with the specified encryption key."
    echo "  --s3-bucket <bucket_name>           Specify the S3 bucket for backup."
    echo "  --s3-region <region_name>           Specify the S3 region for the bucket."
    echo "  --s3-storage-class <sc>             Specify the S3 storage class for the bucket."
    echo "                                      Default to STANDARD. Can be INTELLIGENT_TIERING, STANDARD_IA, GLACIER..."
    echo "  --s3-endpoint-url <url>             Specify the S3 endpoint for the bucket."
    echo "  --ptar                              Use ptar format instead of tar.gz (requires plakar)."
    echo "                                      Provides deduplication, built-in encryption, and versioning."
    echo "  --github-owner <owner>              Backup all repos (mirror), issues, PRs and Projects v2"
    echo "                                      of a GitHub owner (org or user). Requires 'gh', 'git'"
    echo "                                      and 'jq' installed and 'gh auth login' done with scopes:"
    echo "                                      repo, read:org, read:project."
    echo "  --dry                               Validate prerequisites and print every step that would run,"
    echo "                                      but skip the actual archive creation and S3 upload."
    echo "                                      In --github-owner mode also skips the clone and metadata fetch."
    echo
    echo "Examples:"
    echo "  $0 /path/to/source --dest /path/to/destination"
    echo "  $0 /path/to/source --dest /path/to/destination --name backup --enc secretkey"
    echo "  $0 /path/to/source --name backup --enc secretkey --s3-bucket mybucket --s3-region us-east-1"
    echo "  $0 --github-owner my-org --enc secretkey --s3-bucket mybucket --s3-region eu-west-3"
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
S3_ENDPOINT_URL=""
PREFIX_NAME="archive"
SOURCE_PATHS=()
DEST_DIR=""
USE_PTAR=""
GITHUB_OWNER=""
DRY_RUN=""

# Check if zip is installed
if ! command -v zip &> /dev/null; then
    log_error "zip package is not installed. Please install it and try again."
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
        --s3-endpoint-url)
            S3_ENDPOINT_URL=$2
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
        --ptar)
            USE_PTAR="true"
            shift
            ;;
        --github-owner)
            GITHUB_OWNER=$2
            shift 2
            ;;
        --dry)
            DRY_RUN="true"
            shift
            ;;
        *)
            # Assuming the remaining arguments are the sources paths
            SOURCE_PATHS+=("$1")
            shift
            ;;
    esac
done

# GitHub owner backup staging: produce a local directory with mirror clones
# (repos + wikis if enabled via token), issues, PRs and Projects v2 data,
# then feed it into the regular archive/encrypt/S3 pipeline.
if [ -n "$GITHUB_OWNER" ]; then
    # Assert required commands are present (no auto-install)
    GITHUB_TOOL_ERRORS=0
    if ! command -v gh &> /dev/null; then
        log_error "'gh' (GitHub CLI) is required for --github-owner backup but is not installed."
        log_error "Install it from https://cli.github.com/ and retry. This tool is not auto-installed."
        GITHUB_TOOL_ERRORS=1
    fi
    if ! command -v git &> /dev/null; then
        log_error "'git' is required for --github-owner backup but is not installed."
        log_error "Install it via your package manager (e.g. 'sudo apt-get install -y git') and retry."
        GITHUB_TOOL_ERRORS=1
    fi
    if ! command -v jq &> /dev/null; then
        log_error "'jq' is required for --github-owner backup but is not installed."
        log_error "Install it via your package manager (e.g. 'sudo apt-get install -y jq') and retry."
        GITHUB_TOOL_ERRORS=1
    fi
    if [ "$GITHUB_TOOL_ERRORS" -ne 0 ]; then
        exit 1
    fi

    # Authentication is delegated entirely to the gh CLI. The user must have
    # run 'gh auth login' beforehand; we do not accept a token via flag or env.
    if ! gh auth status >/dev/null 2>&1; then
        log_error "GitHub CLI is not authenticated."
        log_error "Run 'gh auth login --scopes \"repo,read:org,read:project\"' before using --github-owner."
        exit 1
    fi

    # Verify the owner (org or user) is reachable with the gh CLI's existing authentication
    if ! gh api "users/$GITHUB_OWNER" >/dev/null 2>&1; then
        log_error "Cannot access GitHub owner '$GITHUB_OWNER' with the current gh authentication."
        log_error "Verify the org name and that 'gh auth status' shows scopes: repo, read:org, read:project."
        exit 1
    fi

    STAGING_DIR=$(mktemp -d -t backupcli-github-XXXXXX)
    # Guarded cleanup: only wipe the staging dir if the variable is set,
    # still points to an existing directory, and matches the exact mktemp
    # prefix we created it with. Prevents any accidental expansion from
    # turning this into a destructive rm.
    cleanup_staging() {
        if [ -n "${STAGING_DIR:-}" ] \
           && [ -d "$STAGING_DIR" ] \
           && [[ "$STAGING_DIR" == */backupcli-github-* ]]; then
            rm -rf -- "$STAGING_DIR"
        fi
    }
    trap cleanup_staging EXIT
    log_info "Staging GitHub backup for '$GITHUB_OWNER' in $STAGING_DIR"
    mkdir -p "$STAGING_DIR/repos" "$STAGING_DIR/meta" "$STAGING_DIR/projects"

    log_info "Listing repos for '$GITHUB_OWNER'..."
    if ! REPO_LIST_JSON=$(gh repo list "$GITHUB_OWNER" --limit 10000 --json name,diskUsage); then
        log_error "Failed to list repos for '$GITHUB_OWNER'."
        exit 1
    fi
    REPO_NAMES=$(printf '%s' "$REPO_LIST_JSON" | jq -r '.[].name')
    REPO_COUNT=$(printf '%s\n' "$REPO_NAMES" | grep -c . || true)
    # GitHub's diskUsage is reported in KB; convert to bytes for downstream size accounting.
    GITHUB_ESTIMATED_BYTES=$(printf '%s' "$REPO_LIST_JSON" | jq '([.[].diskUsage] | add // 0) * 1024')
    GITHUB_ESTIMATED_HR=$(numfmt --to=iec --suffix=B "$GITHUB_ESTIMATED_BYTES" 2>/dev/null || echo "${GITHUB_ESTIMATED_BYTES}B")
    log_info "Found $REPO_COUNT repo(s) to back up, estimated mirror size: ~$GITHUB_ESTIMATED_HR"

    if [ -n "$DRY_RUN" ]; then
        log_info "[dry] Would mirror-clone $REPO_COUNT repo(s) into $STAGING_DIR/repos/<repo>.git"
        log_info "[dry] For each repo, would fetch via gh api: issues, issue comments, pulls, PR review comments, releases (REST, paginated, per_page=100), and discussions with their comments+replies (GraphQL, first 100 each on inner connections)"
        log_info "[dry] Would fetch Projects v2 list for '$GITHUB_OWNER' via gh api graphql, then per-project items and fields"
        log_info "[dry] Skipping all clones and gh api calls."
    else
        while IFS= read -r REPO; do
            [ -z "$REPO" ] && continue
            log_info "[$GITHUB_OWNER/$REPO] cloning bare mirror..."
            # gh repo clone uses gh's own authentication; no token ever touches the URL or process args
            if ! gh repo clone "${GITHUB_OWNER}/${REPO}" "$STAGING_DIR/repos/${REPO}.git" -- --mirror --quiet >/dev/null 2>&1; then
                log_warning "[$GITHUB_OWNER/$REPO] mirror clone failed, continuing with metadata only"
            fi

            mkdir -p "$STAGING_DIR/meta/$REPO"
            log_info "[$GITHUB_OWNER/$REPO] fetching issues, PRs, releases, discussions..."
            # gh api --paginate concatenates page arrays; piping through `jq -c '.[]'`
            # turns the stream into JSONL (one record per line) so downstream tools can
            # process repos with tens of thousands of issues without loading all into memory.
            # Subshell pipefail propagates an upstream gh failure into the || log_warning.
            ( set -o pipefail; gh api --paginate "repos/${GITHUB_OWNER}/${REPO}/issues?state=all&per_page=100" 2>/dev/null \
                | jq -c '.[]' > "$STAGING_DIR/meta/$REPO/issues.jsonl" ) \
                || log_warning "[$GITHUB_OWNER/$REPO] issues fetch failed"
            ( set -o pipefail; gh api --paginate "repos/${GITHUB_OWNER}/${REPO}/issues/comments?per_page=100" 2>/dev/null \
                | jq -c '.[]' > "$STAGING_DIR/meta/$REPO/issues_comments.jsonl" ) \
                || log_warning "[$GITHUB_OWNER/$REPO] issue comments fetch failed"
            ( set -o pipefail; gh api --paginate "repos/${GITHUB_OWNER}/${REPO}/pulls?state=all&per_page=100" 2>/dev/null \
                | jq -c '.[]' > "$STAGING_DIR/meta/$REPO/pulls.jsonl" ) \
                || log_warning "[$GITHUB_OWNER/$REPO] pulls fetch failed"
            ( set -o pipefail; gh api --paginate "repos/${GITHUB_OWNER}/${REPO}/pulls/comments?per_page=100" 2>/dev/null \
                | jq -c '.[]' > "$STAGING_DIR/meta/$REPO/pulls_review_comments.jsonl" ) \
                || log_warning "[$GITHUB_OWNER/$REPO] PR review comments fetch failed"
            ( set -o pipefail; gh api --paginate "repos/${GITHUB_OWNER}/${REPO}/releases?per_page=100" 2>/dev/null \
                | jq -c '.[]' > "$STAGING_DIR/meta/$REPO/releases.jsonl" ) \
                || log_warning "[$GITHUB_OWNER/$REPO] releases fetch failed"
            # Discussions are GraphQL-only. The outer discussions connection paginates,
            # but inner comments/replies don't (gh's --paginate only covers the top
            # connection). Fan-out is bounded so we stay under GitHub's 500k node-count
            # ceiling: 50 discussions x 100 comments x 50 replies = 250,000 leaves.
            # Repos with Discussions disabled return an empty array and produce a 0-byte
            # file with no warning.
            ( set -o pipefail; gh api graphql --paginate \
                -f owner="$GITHUB_OWNER" -f name="$REPO" \
                -f query='query($owner: String!, $name: String!, $endCursor: String) {
                    repository(owner: $owner, name: $name) {
                      discussions(first: 50, after: $endCursor) {
                        pageInfo { hasNextPage endCursor }
                        nodes {
                          id number title body url
                          createdAt updatedAt closed closedAt locked upvoteCount answerChosenAt
                          author { login }
                          category { id name slug }
                          comments(first: 100) {
                            nodes {
                              id body createdAt updatedAt isAnswer
                              author { login }
                              replies(first: 50) {
                                nodes { id body createdAt updatedAt author { login } }
                              }
                            }
                          }
                        }
                      }
                    }
                  }' 2>/dev/null \
                | jq -c '.data.repository.discussions.nodes[]?' > "$STAGING_DIR/meta/$REPO/discussions.jsonl" ) \
                || log_warning "[$GITHUB_OWNER/$REPO] discussions fetch failed (insufficient scopes or other API error)"
        done <<< "$REPO_NAMES"

        log_info "Fetching Projects v2 for '$GITHUB_OWNER'..."
        if ( set -o pipefail; gh api graphql --paginate -f org="$GITHUB_OWNER" -f query='
            query($org: String!, $endCursor: String) {
              organization(login: $org) {
                projectsV2(first: 50, after: $endCursor) {
                  pageInfo { hasNextPage endCursor }
                  nodes {
                    id number title url public closed
                    shortDescription readme createdAt updatedAt
                  }
                }
              }
            }' 2>/dev/null \
            | jq -c '.data.organization.projectsV2.nodes[]? | select(. != null)' > "$STAGING_DIR/projects/projects.jsonl" ); then
            PROJECT_NUMBERS=$(jq -r 'select(.number != null) | .number' < "$STAGING_DIR/projects/projects.jsonl" 2>/dev/null | sort -nu)
            while IFS= read -r PROJ_NUM; do
                [ -z "$PROJ_NUM" ] && continue
                log_info "[project #$PROJ_NUM] fetching items and fields..."
                ( set -o pipefail; gh project item-list "$PROJ_NUM" --owner "$GITHUB_OWNER" --format json --limit 10000 2>/dev/null \
                    | jq -c '.items[]?' > "$STAGING_DIR/projects/${PROJ_NUM}_items.jsonl" ) \
                    || log_warning "[project #$PROJ_NUM] items fetch failed"
                ( set -o pipefail; gh project field-list "$PROJ_NUM" --owner "$GITHUB_OWNER" --format json --limit 10000 2>/dev/null \
                    | jq -c '.fields[]?' > "$STAGING_DIR/projects/${PROJ_NUM}_fields.jsonl" ) \
                    || log_warning "[project #$PROJ_NUM] fields fetch failed"
            done <<< "$PROJECT_NUMBERS"
        else
            log_warning "Projects v2 fetch failed (token likely missing 'read:project' scope)"
        fi
    fi

    SOURCE_PATHS+=("$STAGING_DIR")
    if [ "$PREFIX_NAME" = "archive" ]; then
        PREFIX_NAME="github-${GITHUB_OWNER}"
    fi
fi

if [ ${#SOURCE_PATHS[@]} -eq 0 ]; then
    usage
    exit 1
fi

# Verify if at least one source path is provided and valid
if [ ${#SOURCE_PATHS[@]} -eq 0 ]; then
    usage
    log_error "No source path provided."
fi

# Check if plakar is installed when using ptar
if [ -n "$USE_PTAR" ]; then
    if ! command -v plakar &> /dev/null; then
        log_error "plakar is not installed but --ptar was specified."
        log_error "Install it from: https://www.plakar.io/docs/v1.0.6/quickstart/installation/"
        exit 1
    fi
fi

# Verify if at least one source path is provided and valid
VALID_SOURCE_PATHS=()
for SOURCE in "${SOURCE_PATHS[@]}"; do
    if [ -f "$SOURCE" ] || [ -d "$SOURCE" ]; then
        VALID_SOURCE_PATHS+=("$(realpath "$SOURCE")")
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
        log_warning "No --dest and no S3 options: archive will be written to a temporary directory and not uploaded."
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

# Construct the archive file name with date and time as prefix
if [ -n "$USE_PTAR" ]; then
    # ptar format (encryption is built-in, no .gpg extension needed)
    ZIP_FILE="${CURRENT_DATETIME}_${PREFIX_NAME}.ptar"
else
    ZIP_FILE="${CURRENT_DATETIME}_${PREFIX_NAME}.tar.gz"
    if [ -n "${ENCRYPTION_KEY}" ]; then
        ZIP_FILE="$ZIP_FILE.gpg"
    fi
fi
# Strip any trailing slashes from DEST_DIR (preserving '/' as root) so that
# './', '/tmp/foo/', and '/tmp/foo///' all produce a single-slash join below.
NORMALIZED_DEST="$DEST_DIR"
while [[ "$NORMALIZED_DEST" == */ && "$NORMALIZED_DEST" != "/" ]]; do
    NORMALIZED_DEST="${NORMALIZED_DEST%/}"
done
if [ "$NORMALIZED_DEST" = "/" ]; then
    ZIP_FILE_PATH="/${ZIP_FILE}"
else
    ZIP_FILE_PATH="${NORMALIZED_DEST}/${ZIP_FILE}"
fi

# Calculate total size of VALID_SOURCE_PATHS. In dry+--github-owner mode the staging
# directory is intentionally empty (no clones happen), so 'du' would report a misleading
# ~4KB. Use GitHub's reported diskUsage sum as the estimate instead.
if [ -n "$DRY_RUN" ] && [ -n "${GITHUB_ESTIMATED_BYTES:-}" ]; then
    TOTAL_SIZE="$GITHUB_ESTIMATED_BYTES"
else
    TOTAL_SIZE=0
    for SOURCE in "${VALID_SOURCE_PATHS[@]}"; do
        if [ -d "$SOURCE" ]; then
            SIZE=$(du -sb "$SOURCE" | cut -f1)
        else
            SIZE=$(stat -c%s "$SOURCE")
        fi
        TOTAL_SIZE=$((TOTAL_SIZE + SIZE + 4096))
    done
fi

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

if [ -n "$DRY_RUN" ]; then
    if [ -n "$USE_PTAR" ]; then
        log_info "[dry] Would create ptar archive: $ZIP_FILE_PATH"
        if [ -n "$ENCRYPTION_KEY" ]; then
            log_info "[dry]   format: ptar with built-in encryption (passphrase via PLAKAR_PASSPHRASE)"
        else
            log_info "[dry]   format: ptar plaintext (no encryption)"
        fi
    else
        if [ -n "$ENCRYPTION_KEY" ]; then
            log_info "[dry] Would create tar.gz.gpg archive: $ZIP_FILE_PATH"
            log_info "[dry]   pipeline: tar cf - --exclude='*.sock' <sources> | pigz | gpg --symmetric"
        else
            log_info "[dry] Would create tar.gz archive: $ZIP_FILE_PATH"
            log_info "[dry]   pipeline: tar cf - --exclude='*.sock' <sources> | pigz"
        fi
    fi
    log_info "[dry]   sources (${#VALID_SOURCE_PATHS[@]}): ${VALID_SOURCE_PATHS[*]}"
    log_info "[dry]   estimated max size: $TOTAL_SIZE_HR (available in dest: $AVAILABLE_SPACE_HR)"
else
    # Archive and compress, with optional encryption
    log_info "${#VALID_SOURCE_PATHS[@]} files will be archived (maximum $TOTAL_SIZE_HR)..."
    if [ -n "$USE_PTAR" ]; then
        # Use ptar format via plakar (built-in compression, deduplication, and encryption)
        if [ -n "$ENCRYPTION_KEY" ]; then
            # ptar with encryption (passphrase provided via PLAKAR_PASSPHRASE env var)
            PLAKAR_PASSPHRASE="$ENCRYPTION_KEY" plakar ptar -o "$ZIP_FILE_PATH" "${VALID_SOURCE_PATHS[@]}"
        else
            # ptar without encryption (plaintext mode)
            plakar ptar -plaintext -o "$ZIP_FILE_PATH" "${VALID_SOURCE_PATHS[@]}"
        fi
    else
        # Use traditional tar.gz format
        if [ -n "$ENCRYPTION_KEY" ]; then
            # Encrypt the archive with a password
            tar cf - --exclude='*.sock' "${VALID_SOURCE_PATHS[@]}" | pigz | gpg --symmetric --batch --yes --passphrase "$ENCRYPTION_KEY" -o "$ZIP_FILE_PATH"
        else
            # Create a regular, non-encrypted compressed archive
            tar cf - --exclude='*.sock' "${VALID_SOURCE_PATHS[@]}" | pigz > "$ZIP_FILE_PATH"
        fi
    fi

    ZIP_FILE_SIZE=$(get_file_size "$ZIP_FILE_PATH")
    log_info "Archive complete ($ZIP_FILE_SIZE): $ZIP_FILE_PATH"
fi

# Check if both S3 variables are filled
if [ -n "$S3_BUCKET" ] && [ -n "$S3_REGION" ]; then
    S3_ARGS="--region=$S3_REGION --storage-class=$S3_STORAGE_CLASS"
    if [ -n "$S3_ENDPOINT_URL" ]; then
        S3_ARGS="$S3_ARGS --endpoint-url=$S3_ENDPOINT_URL"
    fi
    if [ -n "$DRY_RUN" ]; then
        log_info "[dry] Would upload to S3: aws s3 cp $S3_ARGS \"$ZIP_FILE_PATH\" \"s3://$S3_BUCKET/$ZIP_FILE\""
    else
        echo "Starting S3 process for $ZIP_FILE..."
        aws s3 cp $S3_ARGS "$ZIP_FILE_PATH" "s3://$S3_BUCKET/$ZIP_FILE"
    fi
fi

log_info "End of script."
