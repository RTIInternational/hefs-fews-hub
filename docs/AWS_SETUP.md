# AWS Configuration for Local Development

This project uses AWS CLI and requires credentials for local development.

## Setup Instructions

1. **Copy the example environment file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` and add your AWS credentials:**
   ```
   AWS_ACCESS_KEY_ID=your_actual_access_key
   AWS_SECRET_ACCESS_KEY=your_actual_secret_key
   AWS_DEFAULT_REGION=us-east-2
   ```

3. **Build and run the container:**
   ```bash
   docker-compose up --build
   ```

## How It Works

- **Environment Variables**: AWS credentials are stored in `.env` file (ignored by git)
- **Entrypoint Script**: The `entrypoint.sh` script automatically configures AWS CLI when the container starts
- **Security**: Credentials are never baked into the Docker image
- **Flexibility**: Works for both permanent and temporary (session token) credentials

## Security Best Practices

✅ **DO:**
- Keep your `.env` file local and never commit it
- Use IAM roles with minimal required permissions
- Rotate credentials regularly
- Use temporary credentials when possible

❌ **DON'T:**
- Commit `.env` file to version control
- Share credentials in plain text
- Use root AWS account credentials
- Hard-code credentials in Dockerfile

## Temporary Credentials

If using temporary credentials (e.g., from AWS SSO or assumed roles), add the session token to your `.env`:

```
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_SESSION_TOKEN=your_session_token
AWS_DEFAULT_REGION=us-east-2
```

## Troubleshooting

If AWS CLI is not working:
1. Verify your `.env` file exists and contains valid credentials
2. Check container logs: `docker-compose logs hefs-hub`
3. Verify AWS configuration inside the container:
   ```bash
   docker-compose exec hefs-hub aws configure list
   ```
