# Bitwarden SSH Playbook

## Resetting Master Password
If you forget your master password, delete the encrypted_password.txt file. When you next run the ssh_playbook script, you will be re-prompted to enter your access token linked to the SSH-Key-Access Service Account. You will then be prompted to enter a new master password.