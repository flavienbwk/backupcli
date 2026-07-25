# backupcli

Easy-to-use backup script with S3 and encryption options.

## Install

```bash
git clone https://github.com/flavienbwk/backupcli && cd backupcli
sudo make install
```

## Usage

```bash
Usage: backupcli [options] <source_paths, ...>

Arguments:
  source_paths              Path to the file or directory to be archived.
                            Glob patterns supported.

Options:
  --name <prefix_name>      Specify a prefix name for the archive file.
  --dest <destination_dir>  Path to the directory where the archive will be saved.
                            If not provided, a temporary directory will be used.
                            Might be use omitted for dry-run.
  --enc <encryption_key>    Encrypt the archive with the specified encryption key.
                            The key is visible in the process list: prefer --enc-file.
  --enc-file <key_file>     Encrypt with the passphrase read from <key_file>. The secret
                            never transits through argv, neither here nor in the gpg /
                            plakar child process. Intended for systemd units using
                            LoadCredentialEncrypted= ($CREDENTIALS_DIRECTORY).
                            Mutually exclusive with --enc.
  --s3-bucket <bucket_name> Specify the S3 bucket for backup.
  --s3-region <region_name> Specify the S3 region for the bucket.
  --s3-storage-class <sc>   Specify the S3 storage class for the bucket.
                            Default to STANDARD. Can be INTELLIGENT_TIERING, STANDARD_IA, GLACIER...
  --s3-endpoint-url <url>   Specify the S3 endpoint for the bucket.
  --ptar                    Use ptar format instead of tar.gz (requires plakar).
                            Provides deduplication, built-in encryption, and versioning.
  --github-owner <owner>    Backup all repos (bare mirror), issues, PRs and Projects v2
                            of a GitHub owner (org or user). Requires gh, git and jq,
                            and the gh CLI must already be authenticated via 'gh auth login'.
  --dry                     Validate prerequisites and print every step that would run,
                            but skip the actual archive creation and S3 upload (and the
                            clone + metadata fetch in --github-owner mode).

Examples:
  backupcli /path/to/source --dst /path/to/destination
  backupcli /path/to/source --dst /path/to/destination --name backup --enc secretkey
  backupcli /path/to/source --name backup --enc secretkey --s3-bucket mybucket --s3-region us-east-1
  backupcli --github-owner my-org --enc secretkey --s3-bucket mybucket --s3-region eu-west-3
  backupcli --dry --github-owner my-org --enc secretkey --s3-bucket mybucket --s3-region eu-west-3
```

Example :

```bash
backupcli /path/to/src_dir_or_file --dest /path/to/dest_dir --name gitlab_backup
```

If you want to use S3, first [configure your AWS access and secret keys](https://docs.aws.amazon.com/sdk-for-go/v1/developer-guide/configuring-sdk.html#specifying-credentials).

Then, you can use it this way :

```bash
backupcli /path/to/gitlab_backup_dir --name gitlab_backup --s3-bucket mybucket --s3-region eu-west-3
```

If you want more security, use symmetric encryption :

```bash
backupcli /path/to/gitlab_backup_dir --name gitlab_backup --enc supersecretpassword --s3-bucket mybucket --s3-region eu-west-3
```

`--enc` puts the passphrase in the process list, where any local user can read it with `ps`. For unattended jobs, use `--enc-file` instead and let the tool read the secret from a file, typically one provided by systemd:

```bash
backupcli /path/to/gitlab_backup_dir --name gitlab_backup --enc-file "$CREDENTIALS_DIRECTORY/backup-key" --s3-bucket mybucket --s3-region eu-west-3
```

Notes on the tar.gz pipeline: the archive is encrypted with `gpg --symmetric --cipher-algo AES256`, which is OpenPGP's AES-256 in CFB mode with an MDC integrity check. If your policy requires an AEAD mode, use `--ptar`: plakar encrypts with AES-256-GCM-SIV and derives the key with Argon2id.

To decrypt your encrypted archive :

```bash
gpg --decrypt --batch --passphrase "YourPassphrase" -o myarchive.tar.gz myarchive.tar.gz.gpg
```

## Backing up a GitHub owner (org or user)

The `--github-owner` option takes a bare-mirror clone of every repository owned by a GitHub org or user account, exports issues, PRs and releases as JSON, exports Projects v2 data, and hands the resulting staging directory to the normal archive / encrypt / S3 pipeline.

<details>
<summary>👉 Prerequisites, authentication, archive layout, and restore</summary>

### Prerequisites

These tools must be installed manually before using `--github-owner` (not auto-installed if any is missing):

- [`gh`](https://cli.github.com/) - the GitHub CLI
- `git`
- `jq`

### Authentication

_backupcli_ uses gh's existing auth. Run `gh auth login`, then `gh auth status` to verify.

**Classic PAT** — simplest:

```bash
gh auth login --scopes "repo,read:org,read:project,read:discussion"
```

**Fine-grained PAT** — required if the org disabled classic tokens. Set **Resource owner = `<the-org>`** (not your personal account, otherwise the token only sees public org repos). Org admin must first enable fine-grained PATs at `Settings → Personal access tokens`. Required permissions:

- Repository access: All repositories
- Repository: Contents, Issues, Pull requests, Discussions — Read
- Organization: Projects — Read

Verify the PAT sees the expected repos:

```bash
gh api /orgs/<ORG>/repos --paginate --jq '.[].name' | wc -l
```

Usage Example:

```bash
backupcli \
    --github-owner my-org \
    --enc supersecretpassword \
    --s3-bucket my-backups --s3-region eu-west-3 \
    --s3-storage-class STANDARD_IA
```

> Discussions: outer pagination is full, but each discussion captures only the first 100 comments and the first 50 replies per comment (GraphQL nested connections aren't auto-paginated, and we stay under GitHub's 500k node-count ceiling). Sufficient for nearly all real-world threads; flag if you need deeper coverage.

Issues / PRs / Projects are exported for archival purposes; re-importing them into GitHub requires a separate importer.

</details>

## Using ptar format

The `--ptar` option uses the modern [ptar format](https://www.plakar.io/posts/2025-06-27/it-doesnt-make-sense-to-wrap-modern-data-in-a-1979-format-introducing-.ptar/) from Plakar

<details>
<summary>👉 Install dependencies to use plakar (Debian/Ubuntu)</summary>

```bash
PLAKAR_VERSION=1.1.4
ARCH=$(dpkg --print-architecture)
curl -fsSLO "https://github.com/PlakarKorp/plakar/releases/download/v${PLAKAR_VERSION}/plakar_${PLAKAR_VERSION}_linux_${ARCH}.deb"
curl -fsSLO "https://github.com/PlakarKorp/plakar/releases/download/v${PLAKAR_VERSION}/plakar_${PLAKAR_VERSION}_checksums.txt"
sha256sum --ignore-missing -c "plakar_${PLAKAR_VERSION}_checksums.txt"
sudo apt-get install -y "./plakar_${PLAKAR_VERSION}_linux_${ARCH}.deb"
```

Example usage:

```bash
# Create a ptar archive without encryption
backupcli /path/to/source --dest /path/to/dest --ptar

# Create an encrypted ptar archive
backupcli /path/to/source --dest /path/to/dest --ptar --enc secretpassword

# Upload encrypted ptar to S3
backupcli /path/to/source --ptar --enc secretpassword --s3-bucket mybucket --s3-region eu-west-3

# Same, with the passphrase read from a file instead of argv
backupcli /path/to/source --ptar --enc-file /run/keys/backup-key --s3-bucket mybucket --s3-region eu-west-3
```

With `--enc-file`, plakar is invoked as `plakar -keyfile <file> ptar ...` and `PLAKAR_PASSPHRASE` is removed from its environment, since that variable takes precedence over `-keyfile` and would otherwise silently encrypt the archive under a different secret.

To browse or restore from a ptar archive:

```bash
# List contents
plakar at myarchive.ptar ls

# Restore specific files
plakar at myarchive.ptar restore -to ./recovery /path/to/file

# Non-interactive, passphrase from a file
plakar -keyfile /run/keys/backup-key at myarchive.ptar ls
```

You might want to [setup Buckets Lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-expire-general-considerations.html) to remove a bucket's files after a specific time (e.g: 30 days).

</details>

## CRON example

You might want to use this script in CRON jobs that runs everyday at 2.30 am :

```cron
30 2 * * * backupcli --enc supersecretpassword --s3-bucket mybucket --s3-region eu-west-3 --name gitlab_backup /path/to/gitlab_backup_dir
```

## Tested host providers

Tested with:

- AWS ✅
- OVHCloud ✅
- Scaleway ✅

## Dependencies

- pigz
- gpg
- AWS CLI (optional, for S3 uploads)
- plakar (optional, for --ptar format)
- gh, git, jq (optional, for --github-owner)
- Linux Ubuntu
