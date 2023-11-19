# backupcli

Easy-to-use backup script with S3 and encryption options.

## Install

```bash
git clone https://github.com/flavienbwk/backupcli && cd backupcli
sudo make install
```

## Usage

```bash
Usage: ./backupcli.sh <source_path> [destination_directory] [options]

Arguments:
  source_path              Path to the file or directory to be archived.
  destination_directory    Optional if s3 options provided.
                           Path to the directory where the archive will be saved.
                           If not provided, a temporary directory will be used.

Options:
  --name <prefix_name>      Specify a prefix name for the archive file.
  --enc <encryption_key>    Encrypt the archive with the specified encryption key.
  --s3-bucket <bucket_name> Specify the S3 bucket for backup.
  --s3-region <region_name> Specify the S3 region for the bucket.

Examples:
  ./backupcli.sh /path/to/source /path/to/destination --name backup
  ./backupcli.sh /path/to/source /path/to/destination --name backup --enc secretkey
  ./backupcli.sh /path/to/source --name backup --enc secretkey --s3-bucket mybucket --s3-region us-east-1
```

Example :

```bash
backupcli --name gitlab_backup /path/to/src_dir_or_file /path/to/dest_dir
```

If you want to use S3, first [configure your AWS access and secret keys](https://docs.aws.amazon.com/sdk-for-go/v1/developer-guide/configuring-sdk.html#specifying-credentials).

Then, you can use it this way :

```bash
./backup.sh --s3-bucket mybucket --s3-region eu-west-3 --name gitlab_backup /path/to/gitlab_backup_dir
```

If you want more security, use symmetric encryption :

```bash
./backup.sh --enc supersecretpassword --s3-bucket mybucket --s3-region eu-west-3 --name gitlab_backup /path/to/gitlab_backup_dir
```

## Dependencies

- zip
- [s3backup](https://github.com/tomcz/s3backup)
- Linux Ubuntu
