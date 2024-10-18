"""Utility functions for the RTI HEFS dashboard."""
import os
from pathlib import Path
import shutil
from typing import Union, List
from concurrent import futures
import subprocess
import logging

import boto3

BUCKET_NAME = "ciroh-rti-hefs-data"
FEWS_INSTALL_DIR = Path("/opt", "fews")

s3_client = boto3.client('s3')


def set_up_logger(file_path: Union[str, Path]) -> logging.Logger:
    """Set up a logger for the dashboard."""
    logger = logging.getLogger("HEFS-Dashboard")
    logger.setLevel(logging.INFO)
    handler = logging.FileHandler(file_path)
    handler.setLevel(logging.INFO)
    formatter = logging.Formatter(
        '%(asctime)s,%(msecs)d %(name)s %(levelname)s %(message)s'
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    return logger


def extract_archive(
        archive: Union[str, Path],
        extract_path: Union[str, Path]
 ) -> None:
    """Extract the file from an archive to a specified directory."""
    # NOTE: Assumes only a single file.
    shutil.unpack_archive(archive, extract_path)
    Path(archive).unlink()
    return


def create_start_standalone_command(
        fews_root_dir: Union[str, Path],
        configuration_dir: Union[str, Path]
) -> str:
    """Create a shell alias for running FEWS."""
    # configuration_dir = /home/jovyan/fews/configurations/abrfc_sa_arcful
    # fews_binaries_dir = /opt/fews
    bash_command = f"{fews_root_dir}/linux/jre/bin/java " \
        f"-Dregion.home={configuration_dir} " \
        f"-Xmx100m -splash:{fews_root_dir}/fews-splash.jpg " \
        f"-Djava.library.path={fews_root_dir}/linux " \
        f"-XX:ErrorFile={configuration_dir}/jvm-error.txt -XX:-UsePerfData " \
        f"-cp '{fews_root_dir}/*' Delft.FEWS"
    return bash_command


def _opener(path, flags):
    return os.open(path, flags, 0o755)


def write_shell_file(
        output_file_path: Union[str, Path],
        bash_command: str
) -> None:
    """Write a shell script file to the remote desktop."""
    print(f"Opening and writing {output_file_path} shell script.")
    os.umask(0)
    with open(output_file_path, "w", opener=_opener) as f:
        f.write("#!/bin/bash\n")
        f.write(bash_command)
    return


def write_fews_desktop_shortcut(
        output_filepath: Union[str, Path],
        shell_script_filepath: Union[str, Path],
        rfc_name: str
) -> None:
    """Write a desktop shortcut file to the remote desktop."""
    os.umask(0)
    with open(Path(output_filepath), "w", opener=_opener) as f:
        f.write("[Desktop Entry]\n")
        f.write(f"Name=FEWS.{rfc_name}\n")
        f.write("Type=Application\n")
        f.write(f"Exec={shell_script_filepath}\n")
        f.write("Terminal=false\n")
        f.write("Icon=/opt/fews/linux/fews_large.png\n")
    return


def s3_download_file(remote_filepath: str, local_filepath: str) -> None:
    """Download a file from an S3 bucket."""
    Path(local_filepath).parent.mkdir(exist_ok=True, parents=True)
    s3 = boto3.client('s3')
    s3.download_file(
        BUCKET_NAME, remote_filepath, local_filepath
    )
    return


def s3_download_directory_cli(prefix, local, bucket=BUCKET_NAME):
    """Download a directory from an S3 bucket using AWS CLI."""
    subprocess.run(
            [
                "aws",
                "s3",
                "cp",
                f"s3://{bucket}/{prefix}",
                local,
                "--recursive",
                "--only-show-errors"
            ],
        )
    return


def s3_download_directory(prefix, local, bucket=BUCKET_NAME):
    """Download a directory from an S3 bucket using boto3."""
    client = boto3.client('s3')

    def create_folder_and_download_file(k):
        dest_pathname = os.path.join(local, k)
        if not os.path.exists(os.path.dirname(dest_pathname)):
            os.makedirs(os.path.dirname(dest_pathname))
        # print(f'downloading {k} to {dest_pathname}')
        client.download_file(bucket, k, dest_pathname)

    keys = []
    dirs = []
    next_token = ''
    base_kwargs = {
        'Bucket': bucket,
        'Prefix': prefix,
    }
    while next_token is not None:
        kwargs = base_kwargs.copy()
        if next_token != '':
            kwargs.update({'ContinuationToken': next_token})
        results = client.list_objects_v2(**kwargs)
        contents = results.get('Contents')
        for i in contents:
            k = i.get('Key')
            if k[-1] != '/':
                keys.append(k)
            else:
                dirs.append(k)
        next_token = results.get('NextContinuationToken')
    for d in dirs:
        dest_pathname = os.path.join(local, d)
        if not os.path.exists(os.path.dirname(dest_pathname)):
            os.makedirs(os.path.dirname(dest_pathname))
    with futures.ThreadPoolExecutor() as executor:
        futures.wait(
            [executor.submit(create_folder_and_download_file, k) for k in keys],
            return_when=futures.FIRST_EXCEPTION,
        )
    print("Download complete.")


def s3_list_contents(prefix: str) -> List[str]:
    """List the contents of an S3 bucket."""
    s3 = boto3.client('s3')
    response = s3.list_objects_v2(
        Bucket=BUCKET_NAME,
        Prefix=prefix
    )
    filelist = [content["Key"] for content in response["Contents"]]
    return filelist


# if __name__ == "__main__":
#     s3_download_directory("ABRFC", "/home/sam/temp/abrfc", BUCKET_NAME)
#     pass