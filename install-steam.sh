#!/usr/bin/env bash

# UTMdeck | https://github.com/m7830380-cyber/UTMdeck
# Adapted from Switchdeck by SildurFX | License: GPLv3

set -euo pipefail

REPO_URL="https://github.com/m7830380-cyber/UTMdeck"
REPO_BRANCH="main"
# Pinned Steam binaries are mirrored from Switchdeck (same known-good files)
DOWNGRADE_BASE="https://raw.githubusercontent.com/SildurFX/Switchdeck/main/files/downgrade"

exit_on_error() {
    printf "\nERROR: %s\n" "$1" >&2
    exit 1
}

verify_gzip_archive() {
    local archive="$1"
    [ -f "$archive" ] || return 1
    gzip -t "$archive" 2>/dev/null
}

extract_tar_gz() {
    local archive="$1"
    local dest="$2"
    local label="$3"

    verify_gzip_archive "$archive" || exit_on_error "$label is corrupt or incomplete: $archive"
    tar -xzf "$archive" -C "$dest" || exit_on_error "Failed to extract $label"
}

download_downgrade_file() {
    local filename="$1"
    local dest="$2"
    local primary="${REPO_URL}/raw/${REPO_BRANCH}/files/downgrade/${filename}"
    local fallback="${FALLBACK_DOWNGRADE_BASE}/${filename}"

    try_download() {
        local url="$1"
        wget -q --show-progress -c -t 5 -O "$dest" "$url" || return 1
        [ -s "$dest" ] || return 1
        if [[ "$filename" == *.tar.gz ]]; then
            verify_gzip_archive "$dest" || return 1
        fi
        return 0
    }

    try_download "$primary" && return 0
    rm -f "$dest"
    printf "\nRetrying %s from fallback mirror..\n" "$filename" >&2
    try_download "$fallback"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""

# Resolve downgrade/script source: local clone or download from GitHub
resolve_install_source() {
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/files/downgrade/steam.cfg" ]; then
        printf "\nUsing local UTMdeck files from: %s\n" "$SCRIPT_DIR" >&2
        echo "$SCRIPT_DIR"
        return 0
    fi

    printf "\nDownloading pinned Steam binaries (this may take a few minutes)..\n" >&2
    TEMP_UD="$STEAMROOT/temp_ud"
    mkdir -p "$TEMP_UD/files/downgrade" "$TEMP_UD/files/steam"

    DOWNGRADE_BASE="${REPO_URL}/raw/${REPO_BRANCH}/files/downgrade"
    STEAM_BASE="${REPO_URL}/raw/${REPO_BRANCH}/files/steam"

    for f in steam.cfg linuxarm64.tar.gz linux_x86_64.zip steamui_websrc_all.zip \
             steamrtarm64.tar.gz.partaa steamrtarm64.tar.gz.partab steamrtarm64.tar.gz.partac; do
        if [[ "$f" == *.tar.gz ]]; then
            download_downgrade_file "$f" "$TEMP_UD/files/downgrade/$f" \
                || exit_on_error "Failed to download valid $f (archive corrupt or incomplete)"
        else
            wget -q --show-progress -c -t 5 -O "$TEMP_UD/files/downgrade/$f" "${REPO_URL}/raw/${REPO_BRANCH}/files/downgrade/$f" \
                || wget -q --show-progress -c -t 5 -O "$TEMP_UD/files/downgrade/$f" "${FALLBACK_DOWNGRADE_BASE}/$f" \
                || exit_on_error "Failed to download $f (check your internet connection)"
        fi
    done

    wget -q -t 5 -O "$TEMP_UD/files/steam/launch-steam.sh" "$STEAM_BASE/launch-steam.sh" \
        || exit_on_error "Failed to download launch-steam.sh"
    wget -q -t 5 -O "$TEMP_UD/files/steam/update-utmdeck.sh" "$STEAM_BASE/update-utmdeck.sh" \
        || exit_on_error "Failed to download update-utmdeck.sh"

    echo "$TEMP_UD"
}

apply_downgrade_files() {
    local SRC="$1"
    local DOWNGRADE="$SRC/files/downgrade"

    printf "\nApplying pinned Steam binaries and blocking auto-updates..\n"

    # Lock updates before Steam ever runs — prevents the update loop / socket disconnect crash
    cp -f "$DOWNGRADE/steam.cfg" "$STEAMROOT/steam.cfg"
    chmod 444 "$STEAMROOT/steam.cfg"

    if [ -f "$DOWNGRADE/linuxarm64.tar.gz" ]; then
        mkdir -p "$STEAMROOT/linuxarm64"
        extract_tar_gz "$DOWNGRADE/linuxarm64.tar.gz" "$STEAMROOT/linuxarm64" "linuxarm64.tar.gz"
    fi

    if [ -f "$DOWNGRADE/linux_x86_64.zip" ]; then
        unzip -q -o "$DOWNGRADE/linux_x86_64.zip" -d "$STEAMROOT"
    fi

    if [ -f "$DOWNGRADE/steamui_websrc_all.zip" ]; then
        unzip -q -o "$DOWNGRADE/steamui_websrc_all.zip" "steamui/*" -d "$STEAMROOT"
    fi

    if [ -f "$DOWNGRADE/steamrtarm64.tar.gz.partaa" ]; then
        mkdir -p "$STEAMROOT/steamrtarm64"
        cat "$DOWNGRADE/steamrtarm64.tar.gz.partaa" \
            "$DOWNGRADE/steamrtarm64.tar.gz.partab" \
            "$DOWNGRADE/steamrtarm64.tar.gz.partac" > "$STEAMROOT/temp_steamrtarm64.tar.gz"
        extract_tar_gz "$STEAMROOT/temp_steamrtarm64.tar.gz" "$STEAMROOT/steamrtarm64" "steamrtarm64.tar.gz"
        rm -f "$STEAMROOT/temp_steamrtarm64.tar.gz"
    fi

    cp -f "$SRC/files/steam/launch-steam.sh" "$STEAMROOT/"
    cp -f "$SRC/files/steam/update-utmdeck.sh" "$STEAMROOT/"
    chmod +x "$STEAMROOT/launch-steam.sh" "$STEAMROOT/update-utmdeck.sh"
    chmod -R +x "$STEAMROOT"
}

setup_steam_shortcuts() {
    ln -fsn "$STEAMROOT" "$STEAMHOME/root"
    ln -fsn "$STEAMROOT" "$STEAMHOME/steam"
    ln -fsn "$STEAMROOT/linux32" "$STEAMHOME/sdk32"
    ln -fsn "$STEAMROOT/linux64" "$STEAMHOME/sdk64"
    ln -fsn "$STEAMROOT/linuxarm64" "$STEAMHOME/sdkarm64"
    ln -fsn "$STEAMROOT/ubuntu12_32" "$STEAMHOME/bin32"
    ln -fsn "$STEAMROOT/ubuntu12_64" "$STEAMHOME/bin64"
    ln -fsn "$STEAMHOME/bin32" "$STEAMHOME/bin"
    ln -fsn "$STEAMROOT/steamrtarm64" "$STEAMROOT/steamrtarm32"

    mkdir -p "$HOME/.local/bin"
    ln -fsn "$STEAMROOT/launch-steam.sh" "$HOME/.local/bin/steam"

    MENU_DIR="$HOME/.local/share/applications"
    mkdir -p "$MENU_DIR"

    DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
    mkdir -p "$DESKTOP_DIR"

    DESKTOP_FILE="$MENU_DIR/steam.desktop"
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Steam
Comment=Launch Steam
Exec=$HOME/.local/bin/steam %U
Icon=$STEAMROOT/public/steam_tray_48.tga
Terminal=false
Type=Application
Categories=Game;
MimeType=x-scheme-handler/steam;
EOF

    if [[ "${XDG_CURRENT_DESKTOP}" == *"KDE"* ]]; then
        KDE_MENU_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kio/servicemenus"
        [ -d "$HOME/.local/share/kservices5" ] && KDE_MENU_DIR="$HOME/.local/share/kservices5/ServiceMenus"
        mkdir -p "$KDE_MENU_DIR" "$STEAMROOT/UTMdeck"
        cat << 'EOF' > "$STEAMROOT/UTMdeck/utmdeck-add-game"
#!/bin/sh
TARGET_ITEM="$1"
[ -z "$TARGET_ITEM" ] && exit 1
if ! ps ax | grep -q 'steamrtarm64/[s]team'; then
    kdialog --title Error --error "Require the Steam to be active."
    exit 1
fi
encodedUrl="steam://addnonsteamgame/$(python3 -c "import urllib.parse; print(urllib.parse.quote(\"$TARGET_ITEM\", safe=''))")"
touch /tmp/addnonsteamgamefile
xdg-open $encodedUrl
bn=$(basename "$TARGET_ITEM")
kdialog --passivepopup "$bn has been added to Steam." 5
EOF
        cat > "$KDE_MENU_DIR/addtosteam.desktop" <<EOF
[Desktop Entry]
Type=Service
ServiceTypes=KonqPopupMenu/Plugin
MimeType=application/x-executable;application/x-desktop;
Actions=addToSteam
X-KDE-Priority=TopLevel
Icon=$STEAMROOT/public/steam_tray_48.tga

[Desktop Action addToSteam]
Exec=$STEAMROOT/UTMdeck/utmdeck-add-game %f
Icon=$STEAMROOT/public/steam_tray_48.tga
Name=Add to Steam
EOF
        chmod +x "$STEAMROOT/UTMdeck/utmdeck-add-game" "$KDE_MENU_DIR/addtosteam.desktop"
    fi

    chmod +x "$DESKTOP_FILE"
    ln -fs "$DESKTOP_FILE" "$DESKTOP_DIR/steam.desktop"
    update-desktop-database "$MENU_DIR" 2>/dev/null
}

# Check for terminal
if [ ! -t 0 ]; then
    if command -v konsole >/dev/null 2>&1; then
        exec konsole -e "$0" "$@"
    elif command -v gnome-terminal >/dev/null 2>&1; then
        exec gnome-terminal -- "$0" "$@"
    elif command -v xterm >/dev/null 2>&1; then
        exec xterm -e "$0" "$@"
    fi
fi

# Require ARM64
if [ "$(uname -m)" != "aarch64" ]; then
    exit_on_error "UTMdeck requires an ARM64 (aarch64) system. Detected: $(uname -m)"
fi

# Setup
STEAMHOME="$HOME/.steam"
STEAMROOT="$HOME/.local/share/Steam"
RTARM64ROOT="$STEAMROOT/steamrtarm64"
DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")

# Uninstall conflicting packages and run Ubuntu-specific setup
if command -v apt-get &>/dev/null; then
    dpkg -l | grep -q "^ii  steam-launcher " && {
        printf "\nFound conflicting system steam package. Uninstalling..\n"
        sudo apt-get remove -y steam-launcher
    } || true

    printf "\nInstalling system dependencies for Ubuntu 24.04 ARM64..\n"
    sudo apt-get update -y
    sudo apt-get install -y wget unzip tar zstd steam-devices \
        mesa-vulkan-drivers libvulkan1 vulkan-tools \
        zenity python3 curl

    # Install box64 (Ubuntu 24.04 ships a generic arm64 build)
    if ! command -v box64 &>/dev/null; then
        printf "\nBox64 not found. Installing from Ubuntu repositories..\n"
        sudo apt-get install -y box64
        sudo systemctl restart systemd-binfmt || true
        printf "\nBox64 installation complete.\n"
    else
        printf "\nBox64 is already installed. Skipping installation.\n"
    fi

elif command -v dnf &>/dev/null; then
    (rpm -q steam || rpm -q steam-launcher) &>/dev/null && {
        printf "\nFound conflicting system steam package. Uninstalling..\n"
        sudo dnf remove -y steam steam-launcher
    } || true
    sudo dnf install -y wget unzip tar zstd steam-devices mesa-vulkan-drivers vulkan-tools zenity python3 curl box64
elif command -v pacman &>/dev/null; then
    pacman -Qq steam &>/dev/null && {
        printf "\nFound conflicting system steam package. Uninstalling..\n"
        sudo pacman -Rns --noconfirm steam
    } || true
    sudo pacman -S --noconfirm wget unzip tar zstd steam-devices vulkan-icd-loader vulkan-tools zenity python curl box64
else
    exit_on_error "Unsupported package manager. UTMdeck targets Ubuntu 24.04 (Kubuntu) on ARM64."
fi

# Cleanup pre-existing/orphaned steam desktop files
for file in "$HOME/.local/share/applications/Steam.desktop" \
            "$HOME/.local/share/applications/steam.desktop" \
            "/usr/local/share/applications/Steam.desktop" \
            "/usr/local/share/applications/steam.desktop" \
            "/usr/share/applications/Steam.desktop" \
            "/usr/share/applications/steam.desktop" \
            "$DESKTOP_DIR/Steam.desktop" \
            "$DESKTOP_DIR/steam.desktop"; do
    if [ -f "$file" ]; then
        if [[ "$file" == /usr/* ]]; then
            sudo rm -f "$file"
        else
            rm -f "$file"
        fi
    fi
done

command -v update-desktop-database &>/dev/null && update-desktop-database "$HOME/.local/share/applications" &>/dev/null || true

# Check if either Steam directory exists
if [ -d "$STEAMROOT" ] || [ -d "$STEAMHOME" ]; then
    printf "\nSteam directories already exist.\n"
    read -p "A clean installation is recommended. Would you like to delete them now? (y/N): " choice
    case "$choice" in
        [yY][eE][sS]|[yY])
            printf "\nDeleting %s and %s...\n" "$STEAMROOT" "$STEAMHOME"
            rm -rf "$STEAMROOT"
            rm -rf "$STEAMHOME"
            mkdir -p "$STEAMROOT"
            mkdir -p "$STEAMHOME"
            ln -fsn "$STEAMROOT" "$STEAMHOME/root"
            ln -fsn "$STEAMROOT" "$STEAMHOME/steam"
            ;;
        *)
            printf "\nContinuing with dirty installation..\n"
            shopt -s extglob dotglob
            eval "rm -rf \"$STEAMROOT\"/!(compatibilitytools.d|depotcache|steamapps|userdata)"
            rm -rf "$STEAMHOME"
            mkdir -p "$STEAMROOT"
            mkdir -p "$STEAMHOME"
            ln -fsn "$STEAMROOT" "$STEAMHOME/root"
            ln -fsn "$STEAMROOT" "$STEAMHOME/steam"
            ;;
    esac
else
    printf "\nNo existing Steam installation found. Performing fresh setup..\n"
    mkdir -p "$STEAMROOT"
    mkdir -p "$STEAMHOME"
    ln -fsn "$STEAMROOT" "$STEAMHOME/root"
    ln -fsn "$STEAMROOT" "$STEAMHOME/steam"
fi

if [ ! -x "$RTARM64ROOT/steam" ]; then
    printf "\nDownloading steam bootstrap..\n"
    mkdir -p "$STEAMROOT/package"
    rm -f "$STEAMROOT/package/beta"
    echo "publicbeta" > "$STEAMROOT/package/beta"
    chmod 444 "$STEAMROOT/package/beta"
    wget -q --show-progress -c -t 5 -O "$STEAMROOT/linuxarm64.zip" "https://client-update.steamstatic.com/bins_linuxarm64_linuxarm64.zip.f523fa87fc6b9b5435a5e7370cb0d664ef53b50b" || exit_on_error "steam bootstrap download failed (check your internet connection)"
    unzip -d "$STEAMROOT" "$STEAMROOT/linuxarm64.zip" "steamrtarm64/steam"
    chmod +x "$RTARM64ROOT/steam"
    rm -rf "$STEAMROOT/linuxarm64.zip"
fi

if [ ! -x "$RTARM64ROOT/pv-runtime/steam-runtime-steamrt-arm64" ]; then
    printf "\nFetching current Steam runtime version..\n"
    VERSION=$(wget -qO- "https://repo.steampowered.com/steamrt3c/images/latest-public-beta.txt" | tr -d '[:space:]') && [ -n "$VERSION" ] || exit_on_error "failed to retrieve the version number from Steam repository"
    printf "\nDownloading steam-runtime version %s..\n" "$VERSION"
    mkdir -p "$RTARM64ROOT/pv-runtime"
    wget -q --show-progress -c -t 5 -O "$RTARM64ROOT/pv-runtime/steam-runtime-steamrt-arm64.tar.xz" "https://repo.steampowered.com/steamrt3c/images/${VERSION}/steam-runtime-steamrt-arm64.tar.xz" || exit_on_error "steam runtime download failed (check your internet connection)"
    tar -xf "$RTARM64ROOT/pv-runtime/steam-runtime-steamrt-arm64.tar.xz" --directory "$RTARM64ROOT/pv-runtime" --checkpoint=200 --checkpoint-action=dot
    rm -rf "$RTARM64ROOT/pv-runtime/steam-runtime-steamrt-arm64.tar.xz"
fi

if [ ! -d "$STEAMROOT/UTMdeck/DXVK" ]; then
    printf "\nDownloading DXVK-Sarek..\n"
    mkdir -p "$STEAMROOT/UTMdeck/DXVK"

    LATEST_JSON=$(wget -qO- "https://api.github.com/repos/pythonlover02/DXVK-Sarek/releases/latest")
    DXVK_URL=$(echo "$LATEST_JSON" | sed -n 's/.*"browser_download_url": "\([^"]*\)".*/\1/p' | head -1)
    DXVK_TAG=$(echo "$LATEST_JSON" | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -1)

    [ -z "$DXVK_URL" ] && exit_on_error "GitHub API returned empty DXVK-Sarek download URL"

    wget -q --show-progress -c -t 5 -O "$STEAMROOT/UTMdeck/DXVK/dxvk-sarek.tar.gz" "$DXVK_URL"
    tar -xzf "$STEAMROOT/UTMdeck/DXVK/dxvk-sarek.tar.gz" --directory "$STEAMROOT/UTMdeck/DXVK" --strip-components=1
    rm -f "$STEAMROOT/UTMdeck/DXVK/dxvk-sarek.tar.gz"

    echo "$DXVK_TAG" > "$STEAMROOT/UTMdeck/dxvk-sarek_version.txt"
    printf "\nDXVK-Sarek installed successfully in UTMdeck/DXVK.\n"
fi

if [ ! -d "$STEAMROOT/UTMdeck/VKD3D" ]; then
    printf "\nDownloading VKD3D-Proton 2.3.1..\n"
    mkdir -p "$STEAMROOT/UTMdeck/VKD3D"

    VK_URL="https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v2.3.1/vkd3d-proton-2.3.1.tar.zst"

    command -v zstd >/dev/null || { printf "\nzstd is missing. Installing dependency.. (Requires sudo)\n"; [ -f /etc/fedora-release ] && sudo dnf install zstd -y || sudo apt install zstd -y; }

    wget -q --show-progress -c -t 5 -O "$STEAMROOT/UTMdeck/VKD3D/vkd3d.tar.zst" "$VK_URL"
    tar -xf "$STEAMROOT/UTMdeck/VKD3D/vkd3d.tar.zst" --directory "$STEAMROOT/UTMdeck/VKD3D" --strip-components=1
    rm -f "$STEAMROOT/UTMdeck/VKD3D/vkd3d.tar.zst"

    printf "\nVKD3D installed successfully in UTMdeck/VKD3D.\n"
fi

# Fix controller permissions
CONTROLLER_RELOAD=0
if command -v apt-get &>/dev/null; then
    dpkg -s steam-devices &>/dev/null || {
        printf "\nConfiguring controller permissions.. (Requires sudo)\n"
        sudo apt-get update && sudo apt-get install -y steam-devices && CONTROLLER_RELOAD=1
    }
elif command -v dnf &>/dev/null; then
    rpm -q steam-devices &>/dev/null || {
        printf "\nConfiguring controller permissions.. (Requires sudo)\n"
        sudo dnf install -y steam-devices && CONTROLLER_RELOAD=1
    }
elif command -v pacman &>/dev/null; then
    pacman -Qi steam-devices &>/dev/null || {
        printf "\nConfiguring controller permissions.. (Requires sudo)\n"
        sudo pacman -S --noconfirm steam-devices && CONTROLLER_RELOAD=1
    }
else
    if [ ! -f /etc/udev/rules.d/70-uinput.rules ]; then
        printf "\nConfiguring controller permissions.. (Requires sudo)\n"
        printf "No supported package manager found. Configuring manually..\n"
        sudo sh -c "mkdir -p /etc/udev/rules.d && echo 'KERNEL==\"uinput\", SUBSYSTEM==\"misc\", TAG+=\"uaccess\", OPTIONS+=\"static_node=uinput\"' > /etc/udev/rules.d/70-uinput.rules"
        sudo modprobe uinput || true
        CONTROLLER_RELOAD=1
    fi
fi

if [ "$CONTROLLER_RELOAD" -eq 1 ]; then
    sudo udevadm control --reload-rules
    sudo udevadm trigger --sysname-match=uinput 2>/dev/null || sudo udevadm trigger
    printf "\nController permissions applied successfully.\n"
fi

# Setup password rule for UD_SWAP and UD_ZRAM
SUDOERS_FILE="/etc/sudoers.d/utmdeck"
if [ ! -f "$SUDOERS_FILE" ]; then
    printf "\nSetting up permissions for UD_SWAP and UD_ZRAM.. (Requires sudo)\n"
    CURRENT_USER=$(whoami)
    RULE_LINE="$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/sbin/swapon, /usr/sbin/swapoff, /usr/sbin/zramctl, /usr/bin/dd, /usr/bin/chmod, /usr/sbin/mkswap"
    if ! sudo sh -c "echo \"$RULE_LINE\" > \"$SUDOERS_FILE\" && chown root:root \"$SUDOERS_FILE\" && chmod 0440 \"$SUDOERS_FILE\""; then
        printf "\nFailed to set up permissions for UD_SWAP and UD_ZRAM.\n"
    fi
    printf "\nOptimizing ZRAM Config.. (Requires sudo)\n"
    sudo mkdir -p /etc/sysctl.d
    sudo tee /etc/sysctl.d/99-zram.conf << 'EOF' >/dev/null
vm.swappiness=100
vm.page-cluster=0
EOF
    sudo sysctl --system >/dev/null 2>&1 || true
fi

if [ -x "$RTARM64ROOT/steam" ]; then
    INSTALL_SRC="$(resolve_install_source)"
    apply_downgrade_files "$INSTALL_SRC"
    setup_steam_shortcuts

    if [ "$INSTALL_SRC" = "$STEAMROOT/temp_ud" ]; then
        rm -rf "$STEAMROOT/temp_ud"
    fi

    printf "\nInstallation complete!\n"
    printf "Steam was NOT launched during install (avoids update loops).\n"
    printf "Launch Steam now with the desktop shortcut or: steam\n\n"
    sleep 3
fi
