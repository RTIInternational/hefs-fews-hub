#!/bin/bash
set -e

# Configure AWS CLI if credentials are provided via environment variables
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Configuring AWS CLI with provided credentials..."
    
    # Ensure .aws directory exists
    mkdir -p /home/jovyan/.aws
    
    # Configure AWS credentials
    cat > /home/jovyan/.aws/credentials <<EOF
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF

    # Add session token if provided (for temporary credentials)
    if [ -n "$AWS_SESSION_TOKEN" ]; then
        echo "aws_session_token = ${AWS_SESSION_TOKEN}" >> /home/jovyan/.aws/credentials
    fi
    
    # Configure AWS region
    cat > /home/jovyan/.aws/config <<EOF
[default]
region = ${AWS_DEFAULT_REGION:-us-east-2}
output = json
EOF
    
    # Set proper ownership
    chown -R jovyan:100 /home/jovyan/.aws
    chmod 600 /home/jovyan/.aws/credentials
    chmod 644 /home/jovyan/.aws/config
    
    echo "AWS CLI configuration complete!"
else
    echo "No AWS credentials provided. Skipping AWS CLI configuration."
    echo "To configure AWS, provide AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables."
fi

# Disable xfce-polkit autostart if it exists (prevents PolicyKit Agent error)
mkdir -p /home/jovyan/.config/autostart
cat > /home/jovyan/.config/autostart/xfce-polkit.desktop <<EOF
[Desktop Entry]
Hidden=true
EOF

# Execute the main command
exec "$@"
