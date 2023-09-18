#!/bin/bash

#########
# SETUP #
#########
# Install all utilities required
# Check if jq is installed using dpkg
if ! dpkg -l | grep -q "jq"; then
    echo "Installing JQ"
    sudo apt-get install jq -y
fi

# Check if 'bws' (Bitwarden CLI Filename) is in the same directory
if [ ! -f ./bws ]; then
    echo "Installing Zip"
    sudo apt-get install zip -y
    echo "Installing Unzip"
    sudo apt-get install unzip -y

    BITWARDEN_CLI_DOWNLOAD_URL="https://github.com/bitwarden/sdk/releases/download/bws-v0.3.0/bws-x86_64-unknown-linux-gnu-0.3.0.zip"
    echo "Downloading Bitwarden CLI"
    wget $BITWARDEN_CLI_DOWNLOAD_URL
    unzip bws-x86_64-unknown-linux-gnu-0.3.0.zip
    rm bws-x86_64-unknown-linux-gnu-0.3.0.zip
else
    echo "Bitwarden CLI 'bws' is already present in the directory."
fi

ENCRYPTED_PASSWORD_FILE="encrypted_password.txt"
DECRYPTED_PASSWORD_FILE="password.txt"
BITWARDEN_CLI_TOKEN=""

# Check if the encrypted password file exists
if [ -f "$ENCRYPTED_PASSWORD_FILE" ]; then
    # If the encrypted file exists, decrypt it
    openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -iter 1000000 -in "$ENCRYPTED_PASSWORD_FILE" -out "$DECRYPTED_PASSWORD_FILE"
    BITWARDEN_CLI_TOKEN=$(cat "$DECRYPTED_PASSWORD_FILE")
else
    # If the encrypted file doesn't exist, prompt the user for a password
    read -s -p "No CLI Token Found. Enter your Bitwarden SSH-Keys-User CLI Token: " TOKEN
    echo "$TOKEN" > "$DECRYPTED_PASSWORD_FILE"
    chmod 600 "$DECRYPTED_PASSWORD_FILE"
    # Encrypt the token
    echo -e "\nThe encryption password should be considered the master password to access your Bitwarden Secret CLI Token.\n"
    openssl enc -aes-256-cbc -md sha512 -pbkdf2 -iter 1000000 -salt -in "$DECRYPTED_PASSWORD_FILE" -out "$ENCRYPTED_PASSWORD_FILE"
    BITWARDEN_CLI_TOKEN=$(cat "$DECRYPTED_PASSWORD_FILE")
fi

# Clean up the decrypted password file and unused variable
rm "$DECRYPTED_PASSWORD_FILE"
unset TOKEN


###################
# GETTING SECRETS #
###################
# Run the Bitwarden CLI command to list secrets and capture the JSON output
SECRETS_JSON=$(./bws secret list --access-token "$BITWARDEN_CLI_TOKEN")

# List all Systems with SSH Keys for the user to pick
echo -e "\nWhich System to SSH Into?\n"
echo "$SECRETS_JSON" | jq -r --arg input_key "$INPUT_KEY" '.[] | .key'
read -p "Enter System Name: " INPUT_KEY

# Use jq to parse the JSON and extract the value associated with the input key
UNTRIMMED_SSH_PRIVATE_KEY=$(echo "$SECRETS_JSON" | jq -r --arg input_key "$INPUT_KEY" '.[] | select(.key == $input_key) | .value')
# Remove any trailing whitespace which would cause a libcrypto error
SSH_PRIVATE_KEY="${UNTRIMMED_SSH_PRIVATE_KEY#"${UNTRIMMED_SSH_PRIVATE_KEY%%[![:space:]]*}"}"

# Check if the value was found
if [ -n "$SSH_PRIVATE_KEY" ]; then
    key_file=./private_key
    echo "$SSH_PRIVATE_KEY" > "$key_file"
    chmod 600 "$key_file" 
else
    echo "Key '$INPUT_KEY' not found in Bitwarden secrets."
    exit 1
fi

# Get note section from the secret
NOTE=$(echo "$SECRETS_JSON" | jq -r --arg input_key "$INPUT_KEY" '.[] | select(.key == $input_key) | .note')
# Check is note is correctly formatted
if [ -n "$NOTE" ]; then
    USER=$(echo "$NOTE" | sed -n 's/.*user:\([^ ]*\).*/\1/p')
    PUBLICDNS=$(echo "$NOTE" | sed -n 's/.*publicdns:\([^ ]*\).*/\1/p')
else
    echo "Note for Key '$INPUT_KEY' is not configured correctly."
    exit 1
fi


###############
# Perform SSH #
###############
ssh -i "$key_file" $USER@$PUBLICDNS

# Cleanup Temporary Keyfile. This cannot be deleted while SSH is established, or the connection will break
rm "$key_file"