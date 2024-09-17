# hefs-fews-hub
A Docker file and collection of python scripts supporting the exploration of HEFS ensembles using FEWS within the TEEHRHub jupyterhub deployment. Part of a CIROH-supported project.

### Using AWS cli
An AWS s3 bucket was created: `ciroh-rti-hefs-data`. Read permissions are publicly available however you will need special credentials to write to the bucket.

To install AWS CLI (linux):



Specify your AWS credentials:

```bash
aws configure
```

You will see something like:
```bash
AWS Access Key ID [None]:
AWS Secret Access Key [None]:
Default region name [None]:
Default output format [None]:
```
Enter your access key, secret access key and `us-east-2` for region name.

To list data in the s3 bucket:
```bash
aws s3 ls ciroh-rti-hefs-data
```

To copy local data to the bucket:
```bash
aws s3 cp <local_filename> s3://ciroh-rti-hefs-data/<remote_filename>
```

To recursively copy a local directory to s3:
```bash
aws s3 cp <path to local dir> s3://ciroh-rti-hefs-data/ --recursive
```

To download s3 objects to local:
```bash
aws s3 cp s3://ciroh-rti-hefs-data/<remote_filename> <local_filename>
```


More details are listed here: [AWS CLI cp Reference](https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html)

## TODO: Include more detailed instructions on getting started
### Logging into TEEHRHub
* Requires github credentials
* Create a free account if you don't have one

### Selecting and configuring your FEWS standalone

Dashboard approach:
1. Start up TEEHRHub
2. Select appropriate image
3. Go to Remote Desktop
4. Click on "Launch" icon to launch dashboard
5. Select the desired standalone
6. Click `Configure Standalone` button
7. Double-click the FEWS desktop icon when it appears

OR, Notebook approach:
1. Run the notebook `dashboard.ipynb`
2. Follow steps 5-7 above