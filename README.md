# backupcli

Easy-to-use backup script with S3 and encryption options.

## Install

```bash
git clone https://github.com/flavienbwk/backupcli && cd backupcli
sudo make install
```

## Usage

```bash
Usage: backupcli <source_path> [options]

Arguments:
  source_path              Path to the file or directory to be archived.

Options:
  --name <prefix_name>      Mandatory. Specify a prefix name for the archive file.
  --dest <destination_dir>  Optional if s3 options provided.
                            Path to the directory where the archive will be saved.
                            If not provided, a temporary directory will be used.
  --enc <encryption_key>    Encrypt the archive with the specified encryption key.
  --s3-bucket <bucket_name> Specify the S3 bucket for backup.
  --s3-region <region_name> Specify the S3 region for the bucket.

Examples:
  backupcli --name backup /path/to/source /path/to/destination
  backupcli --name backup --enc secretkey /path/to/source /path/to/destination
  backupcli --name backup --enc secretkey --s3-bucket mybucket --s3-region us-east-1 /path/to/source
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

## CRON example

You might want to use this script in CRON jobs that runs everyday at 2.30 am :

```cron
30 2 * * * backupcli --enc supersecretpassword --s3-bucket mybucket --s3-region eu-west-3 --name gitlab_backup /path/to/gitlab_backup_dir
```

## Dependencies

- zip
- [s3backup](https://github.com/tomcz/s3backup)
- Linux Ubuntu
