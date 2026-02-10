#!/bin/bash
set -e

# Configure AWS CLI if credentials are provided via environment variables
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Configuring AWS CLI with provided credentials..."
    
    # Ensure .aws directory exists
    mkdir -p ${HOME}/.aws
    
    # Configure AWS credentials
    cat > ${HOME}/.aws/credentials <<EOF
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF

    # Add session token if provided (for temporary credentials)
    if [ -n "$AWS_SESSION_TOKEN" ]; then
        echo "aws_session_token = ${AWS_SESSION_TOKEN}" >> ${HOME}/.aws/credentials
    fi
    
    # Configure AWS region
    cat > ${HOME}/.aws/config <<EOF
[default]
region = ${AWS_DEFAULT_REGION:-us-east-2}
output = json
EOF
    
    # Set proper ownership
    chown -R jovyan:100 ${HOME}/.aws
    chmod 600 ${HOME}/.aws/credentials
    chmod 644 ${HOME}/.aws/config
    
    echo "AWS CLI configuration complete!"
else
    echo "No AWS credentials provided. Skipping AWS CLI configuration."
    echo "To configure AWS authentication in the container, provide AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables."
fi

# Disable xfce-polkit autostart if it exists (prevents PolicyKit Agent error)
mkdir -p ${HOME}/.config/autostart
cat > ${HOME}/.config/autostart/xfce-polkit.desktop <<EOF
[Desktop Entry]
Hidden=true
EOF

# Ensure Desktop directory exists
if [ ! -d "${HOME}/Desktop" ]; then
    echo "Creating Desktop directory..."
    mkdir -p ${HOME}/Desktop
    chown jovyan:100 ${HOME}/Desktop
fi

# Execute the main command
exec "$@"
