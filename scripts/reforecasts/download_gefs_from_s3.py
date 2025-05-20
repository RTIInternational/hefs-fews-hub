"""A script to download GEFS grib2 files from S3 (noaa-gefs-retrospective).

https://noaa-gefs-retrospective.s3.amazonaws.com/index.html

There are separate subdirectories for years 2000 through
2019.

There are then separate subdirectories for each yyyymmddhh, thus 2000010100 to
2000123100 for the year 2000. Under each yyyymmddhh subdirectory, there are
subdirectories c00, p01, p02, p03, p04 for the five individual member
forecasts.

Once per week, 11 reforecast members were computed, and the directories for
those days extend through p10.

Individual grib files have file names such as
“variable_yyyymmddhh_member.grib2”. The variable may have names like “ugrd_pres”
which, in this case, indicates that the variables stored are u-wind components
(east-west) on vertical pressure levels such as the 850 hPa surface.

ref: https://noaa-gefs-retrospective.s3.amazonaws.com/Description_of_reforecast_data.pdf

Up to 10-days are "high-resolution" forecasts:
- 0.25 degree
- 3-hrs time step
- 80 messages

Days 11-16 are "low-resolution":
- 0.5 degree
- 6-hrs time step
- 24 messages

Current variables of interest:
- apcp_sfc
- tmax_2m
- tmin_2m
""" # noqa
from typing import Union, List
from datetime import datetime
from pathlib import Path
import logging
import time

import boto3
import dask
from dask.distributed import Client
import fsspec
import ujson  # fast json
from kerchunk.grib2 import scan_grib
from kerchunk.combine import MultiZarrToZarr
import pandas as pd
import xarray as xr
# from cfgrib.xarray_to_grib import to_grib

GEFS_BUCKET_DIR = "noaa-gefs-retrospective/GEFSv12/reforecast"

RESOLUTION_SPLITS = ["Days:1-10", "Days:10-16"]
VARIABLES = ["apcp_sfc", "tmax_2m", "tmin_2m"]

MESSAGE_JSON_DIR = "/home/sam/temp/gefs_jsons"
MZZ_JSON_DIR = "/home/sam/temp/gefs_mzz_jsons"

# MEMBERS = ["c00", "p01", "p02", "p03", "p04"]  # What about weekly 11-member forecasts?

S3_SO = {
    'anon': True,
    'skip_instance_cache': True
}

FS_LOCAL = fsspec.filesystem('', skip_instance_cache=True, use_listings_cache=False)

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)


def return_ds(json_path: str):
    """Return an xarray dataset from a json file."""
    fs_ = fsspec.filesystem(
        "reference",
        fo=json_path,
        remote_protocol='s3',
        remote_options={'anon': True}
    )
    m = fs_.get_mapper("")
    return xr.open_dataset(
        m,
        engine="zarr",
        backend_kwargs=dict(
            consolidated=False,
            decode_times=False
        )
    )


def combine_variables(
    resolution: str = "Days:1-10",
    concat_dims: List[str] = None
):
    """Combine individual json files into a single file for each resolution."""
    logger.info("Combining json for each variable and specified resolution.")
    for var in VARIABLES:
        json_list = FS_LOCAL.glob(f'{MESSAGE_JSON_DIR}/{var}_*_{resolution}_*.json')
        mzz = MultiZarrToZarr(json_list,
                              concat_dims=concat_dims,
                              remote_protocol='s3',
                              remote_options=dict(anon=True),
                              identical_dims=['latitude', 'longitude'])

        name = f'{MZZ_JSON_DIR}/{var}_{resolution}.json'
        with FS_LOCAL.open(name, 'w') as f:
            f.write(ujson.dumps(mzz.translate()))

        pass


def make_json_name(url, grib_message_number, json_dir):
    p = Path(url).parts
    return f'{json_dir}/{Path(p[8]).stem}_{p[7]}_m{grib_message_number:03d}.json'


@dask.delayed
def gen_json(file_url, json_dir):
    """ref: https://nbviewer.org/gist/rsignell-usgs/ce2c9faeeb006bbd189a8818ffadb133"""
    out = scan_grib(file_url, storage_options=S3_SO)
    for i, message in enumerate(out):  # scan_grib outputs a list containing one reference file per grib message
        out_file_name = make_json_name(file_url, i, json_dir)  # get name
        with FS_LOCAL.open(out_file_name, "w") as f:
            f.write(ujson.dumps(message))  # write to file


def build_zarr_references(
    remote_paths: List[str],
    json_dir: Union[str, Path],
    ignore_missing_file: bool,
) -> list[str]:
    """Build the single file zarr json reference files using kerchunk.

    Parameters
    ----------
    remote_paths : List[str]
        List of remote filepaths.
    json_dir : str or Path
        Local directory for caching json files.

    Returns
    -------
    list[str]
        List of paths to the zarr reference json files.
    """
    logger.info("Building zarr references.")

    json_dir_path = Path(json_dir)
    if not json_dir_path.exists():
        json_dir_path.mkdir(parents=True)

    # fs = fsspec.filesystem("s3", anon=True)

    # Check to see if the jsons already exist locally
    existing_jsons = []
    missing_paths = []
    for path in remote_paths:
        p = path.split("/")
        days = p[8]
        fname = p[-1].split(".")[0]
        local_path = Path(json_dir, f"{fname}.{days}.json")
        if local_path.exists():
            existing_jsons.append(str(local_path))
        else:
            missing_paths.append(path)
    if len(missing_paths) == 0:
        return sorted(existing_jsons)

    results = []
    for path in missing_paths:
        results.append(gen_json(path, json_dir))
    json_paths = dask.compute(results)[0]
    # json_paths.extend(existing_jsons)

    # if not any(json_paths):
    #     raise FileNotFoundError(
    #         "No GEFS files for specified input configuration were found in AWS S3!"
    #     )

    # json_paths = [path for path in json_paths if path is not None]

    # return sorted(json_paths)


def build_remote_gefs_filelist(
    start_date: Union[str, datetime],
    end_date: Union[str, datetime],
    variables: List[str] = VARIABLES,
    member_forecasts: List[str] = ["*"]
):
    """Build a list of GEFS files from S3."""
    logger.info("Building remote GEFS file list.")
    gefs_dir = f"s3://{GEFS_BUCKET_DIR}"
    fs = fsspec.filesystem("s3", anon=True)
    dates = pd.date_range(start=start_date, end=end_date, freq="D")

    component_paths = []

    for dt in dates:
        yyyymmddhh = dt.strftime("%Y%m%d%H")
        hourly_path = (
            f"{gefs_dir}/{dt.year}/{yyyymmddhh}"
        )

        # All members and resolutions for specified variables.
        for variable in variables:
            glob_path = f"{hourly_path}/**/**/{variable}_*.grib2"
            result = fs.glob(glob_path)
            component_paths.extend(result)

        # # If you want to split up the paths for some reason.
        # for variable in variables:
        #     for forecast_resolution in RESOLUTION_SPLITS:
        #         for member in member_forecasts:
        #             glob_path = f"{hourly_path}/{member}/{forecast_resolution}/{variable}_*.grib2"
        #             result = fs.glob(glob_path)
        #             component_paths.extend(result)
        #         logger.warning("BREAK! - Remove this line")
        #         break
        # logger.warning("BREAK! - Remove this line")
        # break

    component_paths = sorted([f"s3://{path}" for path in component_paths])

    return component_paths


def download_from_s3_using_boto3(
    component_paths: List[str],
    local_dir: Union[str, Path]
):
    """Download GEFS files from S3 using boto3."""
    logger.info("Downloading GEFS files from S3 using boto3.")
    obj = boto3.client("s3")

    for s3_path in component_paths:

        subdir = Path(local_dir, Path(s3_path).parts[7].replace(":", ""))
        if not Path(subdir).exists():
            Path(subdir).mkdir(parents=True)

        key = s3_path.replace("s3://noaa-gefs-retrospective/", "")

        obj.download_file(
            Filename=Path(
                local_dir,
                Path(s3_path).parts[7].replace(":", ""),
                Path(s3_path).name
            ),
            Bucket="noaa-gefs-retrospective",
            Key=key
        )
    pass


if __name__ == "__main__":

    t0 = time.time()

    # # ========================================================================
    # # Create combined json files for each variable and resolution.
    # # 1. Build a list of remote GEFS filepaths.
    # # 2. Build zarr references (individual json files).
    # # 3. Combine variables in mzz file.
    # # 4. Open with xaaray.
    # # 5. Subset and write to grib or netcdf.

    # client = Client()
    # logger.info(client.dashboard_link)

    # start_date = "2000-01-01"
    # end_date = "2000-01-01"

    # remote_s3_paths = build_remote_gefs_filelist(
    #     start_date=start_date,
    #     end_date=end_date
    # )

    # json_paths = build_zarr_references(
    #     remote_paths=remote_s3_paths,
    #     json_dir=MESSAGE_JSON_DIR,
    #     ignore_missing_file=True
    # )

    # combine_variables(
    #     resolution="Days:1-10",
    #     concat_dims=["step", "time", "number"]
    # )

    # print(f"Elapsed time: {time.time() - t0}")
    # # ========================================================================

    # Path("/mnt/data/ciroh/hefs/gefs/temp", "test_mzz.nc").unlink()

    # test_path = "/home/sam/temp/gefs_mzz_jsons/apcp_sfc_Days:1-10.json"
    # ds = return_ds(test_path)
    # ds = ds.drop_vars(["surface", "valid_time"])

    # logger.info("Subsetting to CONUS.")
    # # ds_temp = ds.isel(step=1, number=1, time=1)
    # ds_conus = ds.sel(latitude=slice(56, 18), longitude=slice(233, 295))

    # ds_tmp = ds.sel(latitude=slice(77, 15), longitude=slice(175, 240))


    # logger.info("Writing to grib.")
    # Need to set key "endStep" and "stepUnits"? (both int)
    # "GRIB_stepUnits"  # always "1"?
    # ds.tp.attrs["GRIB_stepUnits"] = 1
    # ds.tp.attrs["GRIB_endStep"] = 80  # should this vary?
    # to_grib(ds_conus, Path(MZZ_JSON_DIR, "test_mzz.grib"))
    # ds_xr = xr.open_dataset(Path(MZZ_JSON_DIR, "test_mzz.grib"), engine="cfgrib")

    # pass

    # logger.info("Writing to netcdf.")
    # comp = dict(zlib=True, complevel=5)
    # encoding = {var: comp for var in ds.data_vars}
    # ds_conus.to_netcdf(Path("/mnt/data/ciroh/hefs/gefs/combined", "test_mzz.nc"), encoding=encoding)

    # ========================================================================
    start_date = "2000-01-01"
    end_date = "2000-01-01"

    remote_s3_paths = build_remote_gefs_filelist(
        start_date=start_date,
        end_date=end_date
    )

    # Downloading the raw files from S3 given the remote s3 paths.
    download_from_s3_using_boto3(remote_s3_paths, "/mnt/data/ciroh/hefs/gefs/raw_grib2_test")

    print(f"Elapsed time: {time.time() - t0}")
