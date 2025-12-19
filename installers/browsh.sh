ech "Installing Firefox ( dependency of browsh )"
sudo apt update && sudo apt install firefox -y

echo "Downloading browsh"
wget https://github.com/browsh-org/browsh/releases/download/v1.8.0/browsh_1.8.0_linux_amd64.deb

echo "Installing browsh"
sudo apt install ./browsh_1.8.0_linux_amd64.deb

echo "Removing browsh installer file that was downloaded"
rm browsh_1.8.0_linux_amd64.deb
