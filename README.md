# backupcli

Easy-to-use backup script with S3 and encryption options.

## Install

```bash
git clone https://github.com/flavienbwk/backupcli
sudo make install
```

## Usage

```bash
backupcli /path/to/src_dir_or_file /path/to/dest_dir --name gitlab_backup
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
