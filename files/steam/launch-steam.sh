#!/usr/bin/env bash

# UTMdeck | https://github.com/m7830380-cyber/UTMdeck
# Adapted from Switchdeck by SildurFX | License: GPLv3
#
# Documentation:
# Steam:  https://gist.github.com/davispuh/6600880
#         https://developer.valvesoftware.com/wiki/Command_line_options_(Steam)
# Proton: https://github.com/valvesoftware/proton
# DXVK:   https://github.com/pythonlover02/DXVK-Sarek/blob/main/dxvk.conf
# Box64:  https://github.com/ptitSeb/box64/blob/main/docs/USAGE.md
#
# Per-game launch options (UD_* aliases also accept legacy SD_* names):
#   UD_GAMEMODE=1 %command%  Unload steamwebhelper on game launch (~1GB RAM freed)
#   UD_GAMEMODE=2 %command%  Also stop KDE Plasma background services
#   UD_SWAP=1 %command%       Add swap during the game session
#   UD_ZRAM=1 or 2 %command%  Add 1GB or 2GB zram during the game session

# UTMdeck:
UPDATE_CHECK="true"
ENABLE_GAMEMODE="true"
STEAMDECK_MODE="false"

# Proton:
export PROTON_USE_WOW64=1
export PROTON_DXVK_SAREK=1

# Wine:
export WINEESYNC=0
export PROTON_NO_ESYNC=1
export PROTON_NO_FSYNC=1
export PROTON_NO_NTSYNC=1
export STAGING_WRITECOPY=1
export STAGING_SHARED_MEMORY=1
export __GL_THREADED_OPTIMIZATIONS=1

# DXVK-Sarek:
export DXVK_ALL_CORES=1

# Box64 (tuned for ARM64 VM on iPad):
export BOX64_PROFILE=default
export BOX64_X87_NO80BITS=1
export BOX64_DYNAREC_CALLRET=2
export BOX64_DYNAREC_BIGBLOCK=3

# Disable logging:
export BOX64_LOG=0
export WINEDEBUG=-all
export DXVK_LOG_LEVEL=none

# Steam launch flags:
STEAM_FLAGS=""
STEAM_FLAGS+=" -vrskip"
STEAM_FLAGS+=" -fasthtml"
STEAM_FLAGS+=" -vrdisable"
STEAM_FLAGS+=" -noverifyfiles"
STEAM_FLAGS+=" -nocrashmonitor"
STEAM_FLAGS+=" -no-cef-sandbox"
STEAM_FLAGS+=" -cef-disable-sandbox"
STEAM_FLAGS+=" -cef-single-process"
STEAM_FLAGS+=" -cef-in-process-gpu"
STEAM_FLAGS+=" -cef-disable-breakpad"
STEAM_FLAGS+=" -cef-disable-js-logging"
STEAM_FLAGS+=" -cef-disable-seccomp-sandbox"

if [ "$STEAMDECK_MODE" = "true" ]; then
STEAM_FLAGS+=" -720p"
STEAM_FLAGS+=" -steampal"
STEAM_FLAGS+=" -gamepadui"
STEAM_FLAGS+=" -steamdeck"
fi

########################################################################################################################################

set -o pipefail
shopt -s failglob
set -u

log () {
	echo "launch-steam.sh[$$]: $*" >&2 || :
}

if [ -t 1 ]; then
    echo "Debug Mode Active (Terminal Detected)"
    set -x
    export BOX64_LOG=1
    export WINEDEBUG=""
    export DXVK_LOG_LEVEL=info
else
    exec > /dev/null 2>&1
fi

export TEXTDOMAIN=steam
export TEXTDOMAINDIR=/usr/share/locale
export SYSTEM_PATH="$PATH"
export SYSTEM_LD_LIBRARY_PATH="${LD_LIBRARY_PATH-}"
export SYSTEM_ZENITY="$(which zenity 2>/dev/null)"
MAGIC_RESTART_EXITCODE=42
if [ -z ${SYSTEM_ZENITY} ]; then
	export STEAM_ZENITY="zenity"
else
	export STEAM_ZENITY="${SYSTEM_ZENITY}"
fi

STEAMHOME="$HOME/.steam"
STEAMROOT="$HOME/.local/share/Steam"
UTMDECK_DIR="$STEAMROOT/UTMdeck"
CEF_PATH="$STEAMROOT/steamrtarm64/steamwebhelper.sh"
CEF_DUMMY="${CEF_PATH}.dummy"

# check for updates
ONLINE=0
if [ "$UPDATE_CHECK" = "true" ] && [ ! -t 0 ] && ! pidof steam >/dev/null 2>&1; then
    if [ ! -f "$UTMDECK_DIR/.update.lock" ] || [ -n "$(find "$UTMDECK_DIR/.update.lock" -mmin +60 2>/dev/null)" ]; then
        ping -q -c 1 -W 2 8.8.8.8 &>/dev/null && ONLINE=1
    fi
fi

if [ "$ONLINE" -eq 1 ]; then
    UPDATE_CMD="source '$STEAMROOT/update-utmdeck.sh'; sleep 1;"
    if command -v konsole >/dev/null 2>&1; then
        konsole -e bash -c "$UPDATE_CMD"
    elif command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal --wait -- bash -c "$UPDATE_CMD"
    elif command -v xterm >/dev/null 2>&1; then
        xterm -e bash -c "$UPDATE_CMD"
    fi
    touch "$UTMDECK_DIR/.update.lock"
fi

if [ -f "$UTMDECK_DIR/.needs_restart" ]; then
    rm -f "$UTMDECK_DIR/.needs_restart"
    exec "$STEAMROOT/launch-steam.sh" "$@"
fi

C0="$STEAMROOT/steamapps/compatdata/0"
[[ -d "$C0" && ! -L "$C0" ]] && rm -rf "$C0"
[[ ! -e "$C0" ]] && ln -s /dev/null "$C0"

# Patch Proton with DXVK-Sarek and VKD3D v2.3.1
DX_SRC="$UTMDECK_DIR/DXVK"
VK_SRC="$UTMDECK_DIR/VKD3D"

if [ -d "$DX_SRC" ] && [ -d "$VK_SRC" ]; then
    find "$STEAMROOT/steamapps/common" "$STEAMROOT/compatibilitytools.d" -maxdepth 1 \( -name "Proton*" -o -name "GE-Proton*" \) 2>/dev/null | while read -r p_dir; do
        p="$p_dir/files"
        [ -d "$p" ] || continue
        DX_CHECK="$p/lib/wine/dxvk/x86_64-windows/d3d11.dll"
        VK_CHECK="$p/lib/wine/vkd3d-proton/x86_64-windows/d3d12.dll"

        if [ ! -e "$DX_CHECK" ] || [ ! -e "$VK_CHECK" ] || [ ! -L "$DX_CHECK" ] || [ ! -L "$VK_CHECK" ]; then
            log "Patching: $(basename "$p_dir")"

            DX64="$p/lib/wine/dxvk/x86_64-windows"
            DX32="$p/lib/wine/dxvk/i386-windows"
            mkdir -p "$DX64" "$DX32"
            for f in "$DX_SRC/build/x64"/*.dll; do [ -e "$f" ] && ln -sf "$f" "$DX64/${f##*/}"; done
            for f in "$DX_SRC/build/x32"/*.dll; do [ -e "$f" ] && ln -sf "$f" "$DX32/${f##*/}"; done

            VK64="$p/lib/wine/vkd3d-proton/x86_64-windows"
            VK32="$p/lib/wine/vkd3d-proton/i386-windows"
            mkdir -p "$VK64" "$VK32"
            [ -f "$VK_SRC/x64/d3d12.dll" ] && { ln -sf "$VK_SRC/x64/d3d12.dll" "$VK64/d3d12.dll"; ln -sf "$VK_SRC/x64/d3d12.dll" "$VK64/d3d12core.dll"; }
            [ -f "$VK_SRC/x86/d3d12.dll" ] && { ln -sf "$VK_SRC/x86/d3d12.dll" "$VK32/d3d12.dll"; ln -sf "$VK_SRC/x86/d3d12.dll" "$VK32/d3d12core.dll"; }
            log "Done!"
        fi
    done
else
    log "Source folders missing. Run update-utmdeck.sh"
fi

# UTMdeck Gamemode
if [ "$ENABLE_GAMEMODE" = "true" ]; then
    [ ! -f "$CEF_DUMMY" ] && printf "#!/bin/bash\n# Gamemode Dummy\nsleep infinity\n" > "$CEF_DUMMY" && chmod +x "$CEF_DUMMY"
    [ -f "${CEF_PATH}.bak" ] && { [ $(stat -c%s "$CEF_PATH" 2>/dev/null || echo 0) -lt 100 ] || [ -f "/tmp/cef_swapped.lock" ]; } && mv -f "${CEF_PATH}.bak" "$CEF_PATH" && chmod +x "$CEF_PATH" && rm -f "/tmp/cef_swapped.lock"
    PARENT_PID=$$
    (
        exec 2>/dev/null

        renice -n 19 -p $BASHPID >/dev/null 2>&1
        LOCK_FILE="/tmp/utmdeck_gamemode.pid"
        if [ -f "$LOCK_FILE" ] && kill -0 $(cat "$LOCK_FILE") 2>/dev/null; then exit 0; fi
        echo $$ > "$LOCK_FILE"

        find_gamemode_pid() {
            for p in /proc/[0-9]*; do
                [ -r "$p/environ" ] && grep -zqE "^(UTMDECK_GAMEMODE|UD_GAMEMODE|SD_GAMEMODE|SWITCHDECK_GAMEMODE|SD_GAMEMODE)=" "$p/environ" 2>/dev/null && echo "${p##*/}" && return 0
            done
            return 1
        }
        is_steam_running() {
            for p in /proc/[0-9]*; do
                [ -r "$p/comm" ] && read -r c < "$p/comm" 2>/dev/null && [ "$c" = "steam" ] && return 0
            done
            return 1
        }
        while true; do
            if ! kill -0 "$PARENT_PID" 2>/dev/null; then
                rm -f "$LOCK_FILE"
                exit 0
            fi
            if ! is_steam_running; then
                sleep 15
                continue
            fi
            GAME_PID=$(find_gamemode_pid)
            if [[ -n "$GAME_PID" ]] && [ ! -f "/tmp/cef_swapped.lock" ]; then
                sleep 3
                GAME_PID=$(find_gamemode_pid)
                [ -z "$GAME_PID" ] && { sleep 15; continue; }

                grep -zqE "^(UTMDECK_GAMEMODE|UD_GAMEMODE|SD_GAMEMODE|SWITCHDECK_GAMEMODE|SD_GAMEMODE)=2" "/proc/$GAME_PID/environ" 2>/dev/null && FLAG=2 || FLAG=1

                RUN_ZRAM=0
                RUN_SWAP=0
                grep -zqE "^(UD_ZRAM|SD_ZRAM)=" "/proc/$GAME_PID/environ" 2>/dev/null && RUN_ZRAM=1
                grep -zqE "^(UD_SWAP|SD_SWAP)=1" "/proc/$GAME_PID/environ" 2>/dev/null && RUN_SWAP=1

                ZRAM_DEV=""
                if [ "$RUN_ZRAM" -eq 1 ]; then
                    ZRAM_SIZE="1G"
                    if grep -zqE "^(UD_ZRAM|SD_ZRAM)=2" "/proc/$GAME_PID/environ" 2>/dev/null; then
                        ZRAM_SIZE="2G"
                    fi
                    ZRAM_DEV=$(sudo /usr/sbin/zramctl --find --algorithm lz4 --size "$ZRAM_SIZE" 2>/dev/null | awk '{print $1}')
                    if [ -n "$ZRAM_DEV" ] && [ -b "$ZRAM_DEV" ]; then
                        sudo /usr/sbin/mkswap "$ZRAM_DEV" >/dev/null 2>&1
                        sudo /usr/sbin/swapon --priority 5 "$ZRAM_DEV" 2>/dev/null
                    fi
                fi
                if [ "$RUN_SWAP" -eq 1 ]; then
                    SWAP_SIZE_MB=2048
                    if [ ! -f "/swapfile" ]; then
                        (
                            sudo dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_SIZE_MB" status=none
                            sudo chmod 600 /swapfile
                            sudo mkswap /swapfile >/dev/null 2>&1
                            [ -f "/swapfile" ] && sudo /usr/sbin/swapon --priority 1 /swapfile 2>/dev/null
                        ) &
                    else
                        sudo /usr/sbin/swapon --priority 1 /swapfile 2>/dev/null
                    fi
                fi

                if [ $(stat -c%s "$CEF_PATH" 2>/dev/null || echo 0) -gt 100 ]; then
                    mv -f "$CEF_PATH" "${CEF_PATH}.bak" && cp -p "$CEF_DUMMY" "$CEF_PATH" && touch "/tmp/cef_swapped.lock"
                fi
                killall -9 steamwebhelper drkonqi 2>/dev/null; pkill -9 -f steamwebhelper.sh 2>/dev/null

                if [ "$FLAG" -eq 2 ]; then
                    systemctl --user stop plasma-plasmashell.service 2>/dev/null
                    killall -9 krunner kded5 kded6 kdeconnectd DiscoverNotifier drkonqi 2>/dev/null
                fi

                while [ -d "/proc/$GAME_PID" ]; do sleep 5; done
                sleep 2

                if [ "$RUN_ZRAM" -eq 1 ] && [ -n "$ZRAM_DEV" ] && [ -b "$ZRAM_DEV" ]; then
                    sudo /usr/sbin/swapoff "$ZRAM_DEV" 2>/dev/null
                    sudo /usr/sbin/zramctl --reset "$ZRAM_DEV" 2>/dev/null
                fi
                if [ "$RUN_SWAP" -eq 1 ]; then
                    sudo /usr/sbin/swapoff /swapfile 2>/dev/null
                fi

                if [ -f "/tmp/cef_swapped.lock" ] && [ -f "${CEF_PATH}.bak" ] && [ $(stat -c%s "${CEF_PATH}.bak" 2>/dev/null || echo 0) -gt 100 ]; then
                    rm -f "$CEF_PATH" && mv -f "${CEF_PATH}.bak" "$CEF_PATH" && chmod +x "$CEF_PATH" && rm -f "/tmp/cef_swapped.lock"
                fi
                pkill -9 -f steamwebhelper.sh 2>/dev/null; killall -9 steamwebhelper 2>/dev/null

                if [ "$FLAG" -eq 2 ]; then
                    systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null
                    V="5"; command -v kstart6 >/dev/null && V="6"
                    kstart$V kded$V >/dev/null 2>&1 && sleep 2
                    systemctl --user start plasma-plasmashell.service 2>/dev/null
                    { kstart$V krunner & } >/dev/null 2>&1
                    unset V
                fi
            fi
            sleep 15
        done
    ) &
fi

if [ -x "$STEAMROOT/steamrtarm64/steam" ]; then
    log "Starting Steam"
    _rtarm=$(ls -d "$STEAMROOT/steamrtarm64/pv-runtime/steam-runtime-steamrt-arm64"/steamrt3c_platform_*/files 2>/dev/null | head -1)
    _rtx64=$(ls -d "$STEAMROOT/steamrt64/pv-runtime/steam-runtime-steamrt"/steamrt3c_platform_*/files 2>/dev/null | head -1)
    export LD_LIBRARY_PATH="$STEAMROOT/steamrtarm64${_rtarm:+:$_rtarm/lib/aarch64-linux-gnu:$_rtarm/lib}:$STEAMROOT/steamrt64${_rtx64:+:$_rtx64/lib/x86_64-linux-gnu:$_rtx64/lib}:${LD_LIBRARY_PATH-}"

    "$STEAMROOT/steamrtarm64/steam" "$@" $STEAM_FLAGS

    STATUS=$?

    export PATH="$SYSTEM_PATH"
    export LD_LIBRARY_PATH="$SYSTEM_LD_LIBRARY_PATH"

    if [ $STATUS -eq $MAGIC_RESTART_EXITCODE ] ; then
        log "Restarting Steam by request"
        exec "$0" "$@"
    fi
    exit $STATUS
fi
