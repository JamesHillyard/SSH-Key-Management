#!/bin/bash
# Script Version: 1.2

# Function to update the script
update_script() {
    remote_version=$(curl -s https://raw.githubusercontent.com/JamesHillyard/SSH-Key-Management/main/ssh_playbook.sh | grep -o 'Script Version: [0-9]\+\(\.[0-9]\+\)*')
    local_version=$(grep -o 'Script Version: [0-9]\+\(\.[0-9]\+\)*' "$0")
    
    if [ "$remote_version" != "$local_version" ]; then
        echo "Updating script..."
        curl -s -o "$0" https://raw.githubusercontent.com/JamesHillyard/SSH-Key-Management/main/ssh_playbook.sh
        chmod +x "$0"
        echo "Script updated to version $remote_version"
        exec "$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")" "$@"
    else
        echo "Script is up to date."
    fi
}

# Function to install required utilities
install_utilities_and_bitwarden_cli() {
    if ! dpkg -l | grep -q "jq"; then
        echo "Installing JQ"
        sudo apt-get install jq -y
    fi

    if [ ! -f ./bws ]; then
        echo "Installing Zip"
        sudo apt-get install zip -y
        echo "Installing Unzip"
        sudo apt-get install unzip -y

        BITWARDEN_CLI_DOWNLOAD_URL="https://github.com/bitwarden/sdk/releases/download/bws-v0.3.0/bws-x86_64-unknown-linux-gnu-0.3.0.zip"
        echo "Downloading Bitwarden CLI"
        wget "$BITWARDEN_CLI_DOWNLOAD_URL"
        unzip bws-x86_64-unknown-linux-gnu-0.3.0.zip
        rm bws-x86_64-unknown-linux-gnu-0.3.0.zip
    fi
}

# Function to handle encrypted password
handle_encrypted_password() {
    ENCRYPTED_PASSWORD_FILE="encrypted_password.txt"
    DECRYPTED_PASSWORD_FILE="password.txt"
    BITWARDEN_CLI_TOKEN=""

    if [ -f "$ENCRYPTED_PASSWORD_FILE" ]; then
        openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -iter 1000000 -in "$ENCRYPTED_PASSWORD_FILE" -out "$DECRYPTED_PASSWORD_FILE"
        BITWARDEN_CLI_TOKEN=$(cat "$DECRYPTED_PASSWORD_FILE")
    else
        read -s -p "No CLI Token Found. Enter your Bitwarden SSH-Keys-User CLI Token: " TOKEN
        echo "$TOKEN" > "$DECRYPTED_PASSWORD_FILE"
        chmod 600 "$DECRYPTED_PASSWORD_FILE"
        echo -e "\nThe encryption password should be considered the master password to access your Bitwarden Secret CLI Token.\n"
        openssl enc -aes-256-cbc -md sha512 -pbkdf2 -iter 1000000 -salt -in "$DECRYPTED_PASSWORD_FILE" -out "$ENCRYPTED_PASSWORD_FILE"
        BITWARDEN_CLI_TOKEN=$(cat "$DECRYPTED_PASSWORD_FILE")
    fi

    rm "$DECRYPTED_PASSWORD_FILE"
    unset TOKEN
}

# Function to get Bitwarden secrets
get_secrets() {
    SECRETS_JSON=$(./bws secret list --access-token "$BITWARDEN_CLI_TOKEN")
}

# Function to select a system and get SSH private key
select_system_and_key() {
    options=($(echo "$SECRETS_JSON" | jq -r '.[] | .key'))
    
    menu_items=()
    for option in "${options[@]}"; do
        menu_items+=("$option" "")
    done
    
    # List all Systems with SSH Keys for the user to pick
    choice=$(whiptail --title "Select a System to Rotate SSH Key" --menu "Choose a system:" 15 50 5 "${menu_items[@]}" 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ]; then
        INPUT_KEY="$choice"
        echo "Selected System Name: $INPUT_KEY"
    else
        echo "You canceled."
        exit 1
    fi
    
    UNTRIMMED_SSH_PRIVATE_KEY=$(echo "$SECRETS_JSON" | jq -r --arg input_key "$INPUT_KEY" '.[] | select(.key == $input_key) | .value')
    SSH_PRIVATE_KEY="${UNTRIMMED_SSH_PRIVATE_KEY#"${UNTRIMMED_SSH_PRIVATE_KEY%%[![:space:]]*}"}"
    
    if [ -n "$SSH_PRIVATE_KEY" ]; then
        OLD_KEY_FILE=./private_key
        echo "$SSH_PRIVATE_KEY" > "$OLD_KEY_FILE"
        chmod 600 "$OLD_KEY_FILE"
    else
        echo "Key '$INPUT_KEY' not found in Bitwarden secrets."
        exit 1
    fi
    
    NOTE=$(echo "$SECRETS_JSON" | jq -r --arg input_key "$INPUT_KEY" '.[] | select(.key == $input_key) | .note')
    
    if [ -n "$NOTE" ]; then
        USER=$(echo "$NOTE" | sed -n 's/.*user:\([^ ]*\).*/\1/p')
        PUBLICDNS=$(echo "$NOTE" | sed -n 's/.*publicdns:\([^ ]*\).*/\1/p')
    else
        echo "Note for Key '$INPUT_KEY' is not configured correctly."
        exit 1
    fi

    SECRET_ID=$(echo "$SECRETS_JSON" | jq -r --arg input_key "$INPUT_KEY" '.[] | select(.key == $input_key) | .id')

}

# Function to generate a new SSH key pair and upload to target instance
generate_and_upload_new_keypair() {
    NEW_KEY_FILE="$INPUT_KEY-New"
    ssh-keygen -t ecdsa -b 521 -f "$NEW_KEY_FILE" -N ''

    # Upload the new public key to your EC2 instance
    cat "$NEW_KEY_FILE.pub" | ssh -i "$OLD_KEY_FILE" "$USER@$PUBLICDNS" 'cat > ~/.ssh/authorized_keys'
}

# Function to update the secret key in Bitwarden Secrets Manager
update_bitwarden_secrets_manager() {
#TODO: The CLI doesn't allow you to edit a secret where the value starts with --: THIS IS AN ISSUE!
    # A leading space makes it work, but this is a workaround and would need to be trimmed in the playbook for it to work
    ./bws secret edit $SECRET_ID --value " $(cat "$NEW_KEY_FILE")" --access-token "$BITWARDEN_CLI_TOKEN"
}

# Function to cleanup Old SSH Private Key and New SSH Public & Private Keys
cleanup() {
    rm "$OLD_KEY_FILE"
    rm "$NEW_KEY_FILE"
    rm "$NEW_KEY_FILE.pub"
}

update_script
install_utilities_and_bitwarden_cli
handle_encrypted_password
get_secrets
select_system_and_key
generate_and_upload_new_keypair
update_bitwarden_secrets_manager
cleanup