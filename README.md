# hefs-fews-hub
A Docker file and collection of python scripts supporting the exploration of HEFS ensembles using FEWS within the TEEHRHub jupyterhub deployment. Part of a CIROH-supported project.

Warning! This is currently highly experimental!

### Signing in to HEFS-FEWS at TEEHR-Hub
1. Go to `https://teehr-hub.rtiamanzi.org/hub/spawn`
2. Sign in with your github account (you'll need to create one if you don't have it)
3. From the list, select `HEFS-FEWS Evaluation System`. Click `Start`
4. When JupyterHub starts, Go to Desktop
5. The first time you login, open the terminal in the Desktop and run `cp /opt/hefs_fews_dashboard/dashboard.desktop .`  This will create a desktop icon to start the dashboard.  You should only need to do this once.
6. Select the RFC you wish to work with
7. Specify a directory path. Data downloaded to the `/home/jovyan` directory will persist between sessions.
8. After downloading the configuration, click the FEWS icon to start FEWS.

Things to watch out for:
* If the remote desktop is idle for too long, you may get logged out and may need to restart TEEHRHub!


### Using AWS CLI to copy files to/from the s3 bucket
An AWS s3 bucket was created: `ciroh-rti-hefs-data`. Read permissions are publicly available however you will need special credentials to write to the bucket.

#### To install AWS CLI (linux):

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

More details on installation are provided here: [AWS CLI install and update instructions](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#getting-started-install-instructions)


#### Authentication with your AWS credentials:

In your terminal run:
```bash
aws configure
```

You will see prompts like:
```bash
AWS Access Key ID [None]:
AWS Secret Access Key [None]:
Default region name [None]:
Default output format [None]:
```
Enter your access key, secret access key and `us-east-2` for region name. Hit enter to accept the default (None) value for output format.

Now you should have access to the s3 bucket using AWS CLI.

#### Copying data to/from the s3 bucket
To list data in the s3 bucket:
```bash
aws s3 ls ciroh-rti-hefs-data
```

To copy a local file to the bucket:
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


### TODO: Logging into TEEHRHub [WIP]
* Requires github credentials
* Create a free account if you don't have one

### TODO: Selecting and configuring your FEWS standalone [WIP]

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