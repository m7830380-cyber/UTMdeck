#!/usr/bin/env bash

# UTMdeck | https://github.com/m7830380-cyber/UTMdeck
# Adapted from Switchdeck by SildurFX | License: GPLv3

set -o pipefail
shopt -s failglob
set -u

REPO="m7830380-cyber/UTMdeck"
REPO_BRANCH="main"

echo "Checking for UTMdeck updates.."

STEAMROOT="$HOME/.local/share/Steam"
UTMDECK_DIR="$HOME/.local/share/Steam/UTMdeck"

LAUNCH_SHA_FILE="$UTMDECK_DIR/launch-steam.sha"
UPDATE_SHA_FILE="$UTMDECK_DIR/update-utmdeck.sha"
LAUNCH_JSON=$(wget -qO- "https://api.github.com/repos/${REPO}/contents/files/steam/launch-steam.sh?ref=${REPO_BRANCH}")
UPDATE_JSON=$(wget -qO- "https://api.github.com/repos/${REPO}/contents/files/steam/update-utmdeck.sh?ref=${REPO_BRANCH}")
LATEST_LAUNCH_SHA=$(echo "$LAUNCH_JSON" | sed -n 's/.*"sha": "\([^"]*\)".*/\1/p' | head -n 1)
LATEST_UPDATE_SHA=$(echo "$UPDATE_JSON" | sed -n 's/.*"sha": "\([^"]*\)".*/\1/p' | head -n 1)

if [ "$LATEST_LAUNCH_SHA" != "$(cat "$LAUNCH_SHA_FILE" 2>/dev/null)" ] || [ ! -f "$STEAMROOT/launch-steam.sh" ]; then
    wget -q --header="Accept: application/vnd.github.v3.raw" -O "$STEAMROOT/launch-steam.sh" "https://api.github.com/repos/${REPO}/contents/files/steam/launch-steam.sh?ref=${REPO_BRANCH}"
    echo "$LATEST_LAUNCH_SHA" > "$LAUNCH_SHA_FILE"
    echo "Updating launch script... You may have to restart Steam to fully apply the update."
    touch "$UTMDECK_DIR/.needs_restart"
    sleep 2
fi
if [ "$LATEST_UPDATE_SHA" != "$(cat "$UPDATE_SHA_FILE" 2>/dev/null)" ] || [ ! -f "$STEAMROOT/update-utmdeck.sh" ]; then
    wget -q --header="Accept: application/vnd.github.v3.raw" -O "$STEAMROOT/update-utmdeck.sh" "https://api.github.com/repos/${REPO}/contents/files/steam/update-utmdeck.sh?ref=${REPO_BRANCH}"
    echo "$LATEST_UPDATE_SHA" > "$UPDATE_SHA_FILE"
    echo "Updating update script... You may have to restart Steam to fully apply the update."
    touch "$UTMDECK_DIR/.needs_restart"
    sleep 2
fi

chmod +x "$STEAMROOT/launch-steam.sh" "$STEAMROOT/update-utmdeck.sh"

# Check for DXVK-Sarek update
DX_DIR="$UTMDECK_DIR/DXVK"
VERSION_FILE="$UTMDECK_DIR/dxvk-sarek_version.txt"
LATEST_JSON=$(wget -qO- "https://api.github.com/repos/pythonlover02/DXVK-Sarek/releases/latest")
LATEST_TAG=$(echo "$LATEST_JSON" | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -1)

if [ "$LATEST_TAG" != "$(cat "$VERSION_FILE" 2>/dev/null)" ] || [ ! -d "$DX_DIR" ]; then
    echo "Updating DXVK-Sarek to $LATEST_TAG.."
    DXVK_URL=$(echo "$LATEST_JSON" | sed -n 's/.*"browser_download_url": "\([^"]*\)".*/\1/p' | head -1)

    [ -z "$DXVK_URL" ] && { echo "Error: GitHub API URL empty. Aborting update to protect current installation."; return 1; }

    rm -rf "$UTMDECK_DIR/x64" "$UTMDECK_DIR/x32"
    rm -rf "$DX_DIR" && mkdir -p "$DX_DIR"

    wget -q --show-progress -c -t 5 -O "$DX_DIR/dxvk-sarek.tar.gz" "$DXVK_URL"
    tar -xzf "$DX_DIR/dxvk-sarek.tar.gz" --directory "$DX_DIR" --strip-components=1
    rm -f "$DX_DIR/dxvk-sarek.tar.gz"

    echo "$LATEST_TAG" > "$VERSION_FILE"
    echo "DXVK-Sarek updated successfully."
fi

# Check if VKD3D is installed
VK_DIR="$UTMDECK_DIR/VKD3D"
VK_URL="https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v2.3.1/vkd3d-proton-2.3.1.tar.zst"

if [ ! -d "$VK_DIR" ]; then
    echo "Missing VKD3D folder. Downloading.."
    mkdir -p "$VK_DIR"

    command -v zstd >/dev/null || { echo "zstd is missing. Installing dependency.. (Requires sudo)"; [ -f /etc/fedora-release ] && sudo dnf install zstd -y || sudo apt-get install zstd -y; }

    wget -q --show-progress -c -t 5 -O "$VK_DIR/vkd3d.tar.zst" "$VK_URL"
    tar -xf "$VK_DIR/vkd3d.tar.zst" --directory "$VK_DIR" --strip-components=1
    rm -f "$VK_DIR/vkd3d.tar.zst"

    echo "VKD3D added successfully."
fi

# Setup password rule for UD_SWAP and UD_ZRAM
SUDOERS_FILE="/etc/sudoers.d/utmdeck"
if [ ! -f "$SUDOERS_FILE" ]; then
    echo "Setting up permissions for UD_SWAP and UD_ZRAM.. (Requires sudo)"
    CURRENT_USER=$(whoami)
    RULE_LINE="$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/sbin/swapon, /usr/sbin/swapoff, /usr/sbin/zramctl, /usr/bin/dd, /usr/bin/chmod, /usr/sbin/mkswap"
    if ! sudo sh -c "echo \"$RULE_LINE\" > \"$SUDOERS_FILE\" && chown root:root \"$SUDOERS_FILE\" && chmod 0440 \"$SUDOERS_FILE\""; then
        echo "Failed to set up permissions for UD_SWAP and UD_ZRAM."
    fi
    echo "Optimizing ZRAM Config.. (Requires sudo)"
    sudo mkdir -p /etc/sysctl.d
    sudo tee /etc/sysctl.d/99-zram.conf << 'EOF' >/dev/null
vm.swappiness=100
vm.page-cluster=0
EOF
    sudo sysctl --system >/dev/null 2>&1
fi
