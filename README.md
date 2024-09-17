# hefs-fews-hub
A Docker file and collection of python scripts supporting the exploration of HEFS ensembles using FEWS within the TEEHRHub jupyterhub deployment. Part of a CIROH-supported project.

## TODO: Include more detailed instructions on getting started
### Logging into TEEHRHub
* Requires github credentials
* Create a free account if you don't have one

### Using AWS cli
An AWS s3 bucket was created: `ciroh-rti-hefs-data`. Read permissions are publicly available however you will need special credentials to write to the bucket.

Specify your AWS credentials (not necessary in TEEHRHub?)

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

To list data from the s3 bucket:
```bash
aws s3 ls ciroh-rti-hefs-data
```

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