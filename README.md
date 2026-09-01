# UTMdeck: Steam ARM64 for iPad Pro via UTM

Run the Steam client on **Ubuntu 24.04 (Kubuntu Desktop)** inside a **UTM virtual machine** on iPad Pro. Adapted from [Switchdeck](https://github.com/SildurFX/Switchdeck) for ARM64 Linux VMs instead of Nintendo Switch hardware.

---

## Prerequisites

### iPad / UTM setup

1. Install **UTM (TrollStore Edition)** on your iPad Pro.
2. Create a new VM with:
   - **Architecture:** ARM64 (aarch64)
   - **RAM:** 8 GB recommended (minimum 6 GB)
   - **Storage:** 64 GB+ free space
   - **Display:** VirtIO-GPU or compatible graphics
3. Install **Ubuntu Server 24.04 ARM64**, then add the desktop:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y kubuntu-desktop
sudo reboot
```

4. After reboot, log into Kubuntu and run all system updates.

### Verify your system

```bash
uname -m          # must print: aarch64
vulkaninfo        # should list at least one Vulkan device (may be llvmpipe/software)
```

---

## Installation

Open a terminal in Kubuntu and run:

```bash
wget https://raw.githubusercontent.com/m7830380-cyber/UTMdeck/main/install-steam.sh
bash install-steam.sh
```

The installer will:

- Install Box64, Vulkan drivers, and other dependencies
- Download and configure Steam ARM64
- Apply a known-good Steam downgrade (avoids illegal-instruction crashes)
- Set up DXVK-Sarek and VKD3D compatibility patches
- Create a desktop shortcut and `~/.local/bin/steam` command

Use the **Steam** desktop shortcut or run `steam` from a terminal to launch.

---

## Post-install Steam settings

1. **Settings → Library:** Enable Low Bandwidth, Low Performance, and Disable Community Content.
2. **Settings → Compatibility:** Select **Proton Experimental** for Windows games.
3. Restart Steam once so DXVK-Sarek and VKD3D patches apply to Proton.

---

## Requirements

| Component | Notes |
|-----------|-------|
| **OS** | Ubuntu 24.04 ARM64 with Kubuntu desktop |
| **VM** | UTM on iPad Pro (8 GB RAM allocated) |
| **Architecture** | aarch64 only |
| **Box64** | Installed automatically (runs x86_64 Proton builds) |
| **Vulkan** | Mesa software/virtio drivers installed automatically |
| **Internet** | Required for initial install and Steam login |

---

## Features

* `UD_GAMEMODE=1 %command%` — Unload steamwebhelper during games (~1 GB RAM freed).
* `UD_GAMEMODE=2 %command%` — Also stop KDE Plasma services for extra RAM.
* `UD_SWAP=1 %command%` — Add 2 GB swap during the game session.
* `UD_ZRAM=1 or 2 %command%` — Add 1 GB or 2 GB zram during the game session.
* [DXVK-Sarek](https://github.com/pythonlover02/DXVK-Sarek) patch for Proton and GE-Proton.
* [VKD3D v2.3.1](https://github.com/HansKristian-Work/vkd3d-proton/releases/tag/v2.3.1) patch for Proton and GE-Proton.
* KDE context menu: **Add to Steam** for importing non-Steam games.
* Auto-update of launch scripts from this repository.

Legacy `SD_*` launch option names from Switchdeck are also accepted.

---

## Performance expectations

Running Steam inside a VM on iPad has significant overhead. Realistic outcomes:

| Goal | Feasibility |
|------|-------------|
| Steam client UI | Good |
| Small native ARM Linux games | Possible |
| Lightweight 2D / indie games via Proton | Maybe, with low settings |
| AAA / demanding 3D games | Unlikely |

Tips for better performance:

- Allocate the maximum RAM your UTM profile allows (8 GB on 16 GB iPad Pro).
- Use `UD_GAMEMODE=1` for memory-heavy games.
- Keep the VM resolution at 1280×720 or lower.
- Set `STEAMDECK_MODE="true"` at the top of `launch-steam.sh` for Big Picture / gamepad UI.

---

## Troubleshooting

**tar: Skipping to next header / archive corrupt**
The pinned Steam archive download was incomplete or corrupted. Fix:

```bash
rm -rf ~/.local/share/Steam ~/.steam
wget https://raw.githubusercontent.com/m7830380-cyber/UTMdeck/main/install-steam.sh
bash install-steam.sh
```

The installer now validates archives before extracting and falls back to the Switchdeck mirror if needed.

**"Installing update" loop / "socket disconnected no more messages are expected"**
Steam tried to auto-update before the pinned binaries were applied. Fix with a clean reinstall:

```bash
rm -rf ~/.local/share/Steam ~/.steam
wget https://raw.githubusercontent.com/m7830380-cyber/UTMdeck/main/install-steam.sh
bash install-steam.sh
```

Answer **yes** to delete existing Steam folders. The updated installer applies the downgrade and `steam.cfg` *before* launching Steam. Verify:

```bash
cat ~/.local/share/Steam/steam.cfg
# should show: BootStrapperInhibitAll=enable
```

**Steam crashes with "illegal instruction"**
The downgrade step should prevent this. Re-run the installer or check that `steam.cfg` exists in your Steam folder with `BootStrapperInhibitAll=enable`.

**No Vulkan device**
```bash
sudo apt install mesa-vulkan-drivers libvulkan1 vulkan-tools
vulkaninfo
```

**Box64 not working**
```bash
sudo apt install box64
sudo systemctl restart systemd-binfmt
```

**Out of memory during games**
Use launch options: `UD_GAMEMODE=1 UD_ZRAM=2 %command%`

---

## Explanation

This project automates Steam ARM64 installation on ARM64 Linux. Newer Steam client builds (after ~April 2026) can cause illegal-instruction crashes on some ARM hardware; UTMdeck pins known-good binaries and blocks auto-updates via `steam.cfg`.

Box64 provides an x86_64 compatibility layer so standard Proton builds can run on ARM64. DXVK-Sarek and VKD3D patches improve compatibility with limited Vulkan support in VM environments.

Based on [Switchdeck](https://github.com/SildurFX/Switchdeck) by SildurFX. Credits to Ivy for the original steam-arm64 download script.

---

## Legal Notice

The bash scripts in this repository are provided under the **GNU General Public License v3.0 (GPL-3.0)**.

The Steam binaries in `/files/downgrade/` are the proprietary property of **Valve Corporation** and are subject to the [Steam Subscriber Agreement](https://store.steampowered.com/subscriber_agreement).

This project is not affiliated with, maintained by, or endorsed by Valve Corporation or Nintendo.
