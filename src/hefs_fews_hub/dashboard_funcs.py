"""Utility functions for the RTI HEFS dashboard."""
import contextlib
import os
from pathlib import Path
import shutil
from typing import Union, List
from concurrent import futures
import subprocess
import logging

logger = logging.getLogger("HEFS-Dashboard")

with contextlib.suppress(ImportError):
    import s3fs
    s3 = s3fs.S3FileSystem(anon=False)

BUCKET_NAME = "ciroh-rti-hefs-data"
FEWS_INSTALL_DIR = Path("/opt", "fews")

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
    s3_path = f"{BUCKET_NAME}/{remote_filepath}"
    s3.get(s3_path, local_filepath)
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
    """Download a directory from an S3 bucket using s3fs."""
    # Ensure local directory exists
    Path(local).mkdir(exist_ok=True, parents=True)
    
    # Construct S3 path
    s3_path = f"{bucket}/{prefix}"
    
    # Get all files in the directory
    files = s3.glob(f"{s3_path}/**")
    
    def download_file(s3_file):
        # Skip directories
        if s3_file.endswith('/'):
            return
        
        # Calculate relative path and local destination
        relative_path = s3_file.replace(f"{bucket}/{prefix}", "").lstrip('/')
        dest_pathname = os.path.join(local, relative_path)
        
        # Create parent directory if needed
        os.makedirs(os.path.dirname(dest_pathname), exist_ok=True)
        
        # Download file
        s3.get(s3_file, dest_pathname)
    
    # Download files in parallel
    with futures.ThreadPoolExecutor() as executor:
        futures.wait(
            [executor.submit(download_file, f) for f in files],
            return_when=futures.FIRST_EXCEPTION,
        )
    print("Download complete.")


def s3_list_contents(prefix: str) -> List[str]:
    """List the contents of an S3 bucket."""
    s3_path = f"{BUCKET_NAME}/{prefix}"
    files = s3.ls(s3_path, detail=False)
    # Remove bucket name from paths to match original behavior
    filelist = [f.replace(f"{BUCKET_NAME}/", "") for f in files]
    return filelist


def install_fews_standalone(download_dir: str, rfc: str) -> None:
    """Download standalone configuration from S3 to the working directory."""
    fews_download_dir = Path(download_dir)
    if not fews_download_dir.exists():
        logger.info(f"The directory: {fews_download_dir}, does not exist. Please create it first!")
        raise ValueError(f"The directory: {fews_download_dir}, does not exist. Please create it first!")

    # 1. Download sa from S3
    logger.info(f"Downloading {rfc} configuration to {fews_download_dir.as_posix()}...This will take a few minutes...")
    s3_download_directory_cli(
        prefix=f"{rfc}/Config",
        local=Path(fews_download_dir, f"{rfc}/Config").as_posix(),
    )
    # 2. Create the bash command to run the standalone configuration
    logger.info("Creating bash command to start FEWS...")
    sa_dir_path = Path(fews_download_dir, rfc)
    bash_command_str = create_start_standalone_command(
        fews_root_dir=FEWS_INSTALL_DIR.as_posix(),
        configuration_dir=sa_dir_path.as_posix()
    )
    # 3. Write the command to start FEWS to a shell script
    logger.info("Writing shell script to start FEWS...")
    shell_script_filepath = Path(sa_dir_path, "start_fews_standalone.sh")
    write_shell_file(shell_script_filepath, bash_command_str)

    # 4. Copy in patch file for the downloaded standalone config.
    logger.info("Downloading patch file and global properties...")
    s3_download_file(
        remote_filepath="fews-install/fews-NA-202102-125264-patch.jar",
        local_filepath=Path(sa_dir_path, "fews-NA-202102-125264-patch.jar")
    )
    logger.info("Downloading sa_global.properties...Temporarily to Config dir.")
    s3_download_file(
        remote_filepath=f"{rfc}/sa_global.properties",
        local_filepath=Path(sa_dir_path, "Config", "sa_global.properties")
    )
    # 5. Create FEWS desktop shortcut that calls the shell script
    desktop_shortcut_filepath = Path(
        Path.home(),
        "Desktop",
        f"{sa_dir_path.name}.desktop"
    )
    logger.info(f"Creating FEWS desktop shortcut...{desktop_shortcut_filepath}")
    write_fews_desktop_shortcut(
        desktop_shortcut_filepath,
        shell_script_filepath,
        rfc
    )
    logger.info("Installation complete.")
    return



# if __name__ == "__main__":
#     s3_download_directory("ABRFC", "/home/sam/temp/abrfc", BUCKET_NAME)
#     pass