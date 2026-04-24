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
  --s3-bucket <bucket_name> Specify the S3 bucket for backup.
  --s3-region <region_name> Specify the S3 region for the bucket.
  --s3-storage-class <sc>   Specify the S3 storage class for the bucket.
                            Default to STANDARD. Can be INTELLIGENT_TIERING, STANDARD_IA, GLACIER...
  --s3-endpoint-url <url>   Specify the S3 endpoint for the bucket.
  --ptar                    Use ptar format instead of tar.gz (requires plakar).
                            Provides deduplication, built-in encryption, and versioning.

Examples:
  backupcli /path/to/source --dst /path/to/destination
  backupcli /path/to/source --dst /path/to/destination --name backup --enc secretkey
  backupcli /path/to/source --name backup --enc secretkey --s3-bucket mybucket --s3-region us-east-1
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

To decrypt your encrypted archive :

```bash
gpg --decrypt --batch --passphrase "YourPassphrase" -o myarchive.tar.gz myarchive.tar.gz.gpg
```

## Using ptar format

The `--ptar` option uses the modern [ptar format](https://www.plakar.io/posts/2025-06-27/it-doesnt-make-sense-to-wrap-modern-data-in-a-1979-format-introducing-.ptar/) from Plakar

<details>
<summary>👉 Install dependencies to use plakar (Debian/Ubuntu)</summary>

```bash
curl -fsSL https://packages.plakar.io/keys/plakar.gpg | sudo gpg --dearmor -o /usr/share/keyrings/plakar.gpg
echo "deb [signed-by=/usr/share/keyrings/plakar.gpg] https://packages.plakar.io/deb stable main" | sudo tee /etc/apt/sources.list.d/plakar.list
sudo apt-get update && sudo apt-get install plakar
```

For other systems, see the [official installation guide](https://www.plakar.io/docs/v1.0.6/quickstart/installation/).

Example usage:

```bash
# Create a ptar archive without encryption
backupcli /path/to/source --dest /path/to/dest --ptar

# Create an encrypted ptar archive
backupcli /path/to/source --dest /path/to/dest --ptar --enc secretpassword

# Upload encrypted ptar to S3
backupcli /path/to/source --ptar --enc secretpassword --s3-bucket mybucket --s3-region eu-west-3
```

To browse or restore from a ptar archive:

```bash
# List contents
plakar at myarchive.ptar ls

# Restore specific files
plakar at myarchive.ptar restore -to ./recovery /path/to/file
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
- Linux Ubuntu
