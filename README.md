# SSH Playbook
This project makes use of the [Bitwarden Secrets Manager](https://bitwarden.com/products/secrets-manager/) to provide a simple command line tool to SSH into any systems in the 'SSH-Keys' project. 

**DevOps Objective:** [Payara Confluence | SSH Key Management](https://payara.atlassian.net/wiki/spaces/ITOPS/pages/3878092836/SSH+Key+Management)

**Author:** James Hillyard

---

# Setup
There is no setup required to run either the SSH Playbook or Key Rotation scripts, they are entirely self contained and will install necessary tools, and the Bitwarden CLI for you. On the first execution, you will be prompted to 'Enter your Bitwarden SSH-Keys-User' CLI Token. This refers to the 'SSH-Keys-Access' service account registered against the project. To create this token follow [this SOP](https://payara.atlassian.net/wiki/spaces/ITOPS/pages/3880419331)

After entrting the CLI token, you will be prompted for an encryption password, this will be used to keep your CLI token secure, and should be treated like your Bitwarden Master Password. You will need to remember this each time you want to use the script.

## Resetting Master Password
If you forget your master password, delete the encrypted_password.txt file with `rm encrypted_password.txt`. When you next run eiher script, you will be re-prompted to enter your access token linked to the SSH-Key-Access Service Account. You will then be prompted to enter a new master password.

# Usage
## Using SSH Playbook
To use the SSH Playbook, simply execute the script with `bash ssh_playbook.sh`. It will prompt you for your master password you setup on the first use, then will open a screen with all systems which can be accessed via this tool. Use the arrow keys to navigate to the system you want to access and press enter. An SSH connection will then be established with that instance.

When you're finished, run 'exit' from the terminal, this will then run the cleanup of the script. If you forget to do this, it's not a problem, the private key will be left in the directory you ran the script from. When you next use the script it will clean it up. This is not ideal, but equivalent to keeping keys in your '.ssh' folder.

## Using Key Rotation
*Feature coming soon*