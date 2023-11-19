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
  --dest <destination_dir>  Optional if --s3-bucket and --s3-region are provided.
                            Path to the directory where the archive will be saved.
                            If not provided, a temporary directory will be used.
  --enc <encryption_key>    Encrypt the archive with the specified encryption key.
  --s3-bucket <bucket_name> Specify the S3 bucket for backup.
  --s3-region <region_name> Specify the S3 region for the bucket.
  --s3-storage-class <sc>   Specify the S3 storage class for the bucket.
                            Default to STANDARD. Can be INTELLIGENT_TIERING, STANDARD_IA, GLACIER...

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

You might want to [setup Buckets Lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-expire-general-considerations.html) to remove a bucket's files after a specific time (e.g: 30 days).

## CRON example

You might want to use this script in CRON jobs that runs everyday at 2.30 am :

```cron
30 2 * * * backupcli --enc supersecretpassword --s3-bucket mybucket --s3-region eu-west-3 --name gitlab_backup /path/to/gitlab_backup_dir
```

## Dependencies

- zip
- AWS CLI
- Linux Ubuntu
