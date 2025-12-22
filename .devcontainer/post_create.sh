sudo apt-get update
sudo apt-get install -y shfmt shellcheck
curl -fsSL -o vault.zip "https://releases.hashicorp.com/vault/1.18.2/vault_1.18.2_linux_amd64.zip"
sudo unzip vault.zip -d /usr/local/bin/
sudo chmod +x /usr/local/bin/vault
rm vault.zip
