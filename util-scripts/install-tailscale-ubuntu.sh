
# 1. **Add Tailscale's package signing key and repository:**
# ```bash
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
# ```

# 2. **Update package list:**
# ```bash
sudo apt-get update
# ```

# 3. **Install Tailscale:**
# ```bash
sudo apt-get install tailscale
# ```

# 4. **Start Tailscale and authenticate:**
# ```bash
sudo tailscale up
# ```

