# Sol OS (`sol-os`) — BC-250 Edition

**Sol OS (BC-250 Edition)** is an immutable, SteamOS-like Linux distribution tailored specifically for the **AMD BC-250** mining/compute APU board (**AMD Oberon / Cyan Skillfish `GFX1013`**, 6-core/12-thread Zen 2 CPU, 24-CU RDNA 2 GPU, 16 GB unified GDDR6).

Built declaratively with [BlueBuild](https://blue-build.org/) on top of `ghcr.io/ublue-os/bazzite-deck:latest`, Sol OS ships a console-first **Steam Game Mode** experience (`gamescope-session-steam`) with a **KDE Plasma** desktop fallback, preconfigured BC-250 GPU SMU governance, sleep/handheld-daemon mitigations, and out-of-the-box **HelixSR** RDNA 2 packed-FP16 upscaling.

---

## 1. Overview & Architecture

| Component | Implementation |
| --- | --- |
| **Base Image** | `ghcr.io/ublue-os/bazzite-deck:latest` (Fedora Atomic / OSTree + `bootc`) |
| **Primary Session** | Steam Game Mode (`gamescope-session-steam`) with KDE Plasma desktop fallback |
| **GPU / SMU Governor** | `cyan-skillfish-governor-smu` (`/usr/libexec/sol-os/cyan-skillfish-governor-smu`, exposed at `/usr/local/bin/cyan-skillfish-governor-smu` via `systemd-tmpfiles`) managed by `cyan-skillfish-governor-smu.service` |
| **Kernel Arguments** | `amdgpu.ppfeaturemask=0xffffffff` (unlocks full `amdgpu` clock/voltage/power controls on Cyan Skillfish) |
| **Sleep / Daemon Fixes** | Masks `sleep.target`, `suspend.target`, `hibernate.target`, `hybrid-sleep.target` (with `/etc/systemd/sleep.conf.d/99-sol-disable-sleep.conf`) and masks `hhd.service` + `hhd@.service` (handheld daemon not applicable to BC-250 boards) |
| **HelixSR Upscaling** | User service `sol-helixsr-setup.service` + system `/usr/lib/systemd/system/plugin_loader.service` (`sol-decky-launch`) + Decky **HelixSR Manager** + `helixsr-update` CLI (`/usr/libexec/sol-os/helixsr-update`, linked at `/usr/local/bin/helixsr-update`) |
| **Sol Eclipse Theme** | `sol-eclipse` Plymouth boot splash (`initramfs`), `sol_startup.webm` Steam Game Mode startup movie, `Sol-Eclipse` CSS Loader theme, and KDE Plasma 6 Global Theme (`org.sol-os.eclipse`) via `sol-theme-setup.service` / `sol-theme-apply` |
| **Included Utilities** | `mangohud` (`terra-mangohud`), `gamescope` (`terra-gamescope`), `lm_sensors`, `radeontop`, `vulkan-tools`, `jq`, `git`, `curl`, `unzip` |
| **Image Signing** | Cryptographically signed via Sigstore `cosign` (`cosign.pub` + GitHub Actions `SIGNING_SECRET`) |

> **Immutable Layout Note:** All Sol OS binaries and scripts live immutably under `/usr/libexec/sol-os/` and are symlinked into `/usr/local/bin/` at boot via `/usr/lib/tmpfiles.d/sol-os-local-bin.conf`, keeping `/usr` atomic across `rpm-ostree` / `bootc` updates.

---

## 2. Required BC-250 BIOS Settings Before Flashing

Before booting the installer or rebasing onto Sol OS, configure the following settings in your BC-250 UEFI/BIOS firmware:

1. **UMA Frame Buffer Size / Dynamic VRAM:** Set to **`512 MB`**.
   - Allows `amdgpu` to allocate VRAM dynamically across the shared **16 GB unified GDDR6** pool instead of permanently reserving excessive memory away from system processes.
2. **IOMMU:** Set to **`Disabled`**.
   - Prevents `amdgpu` DMA remapping and GPU initialization failures on BC-250 boards.
3. **Fan Curve:** Configure an **active PWM fan curve** prior to applying sustained gaming or shader-compilation loads.
   - The BC-250 uses a passive server-style heatsink designed for constant forced airflow; running without adequate active cooling will rapidly trigger thermal throttling (`85 °C`) or shutdowns.
4. **Boot Mode & Secure Boot:**
   - **UEFI Boot:** `Enabled`
   - **Secure Boot:** `Disabled` (or enroll your own Machine Owner Key if your environment requires Secure Boot).

---

## 3. Repository & Signing Setup

Sol OS uses [BlueBuild](https://blue-build.org/) and Sigstore `cosign` in GitHub Actions (`.github/workflows/build.yml`) to build, sign, and publish container images to GitHub Container Registry (`ghcr.io`).

1. **Generate a `cosign` key pair** in the root of your repository:

   ```bash
   cosign generate-key-pair
   ```

   - When prompted for a password, **press `Enter` twice for an empty password** (required for unattended CI builds).
   - This creates `cosign.pub` (safe and required to commit) and `cosign.key` (private key — **never commit**; already ignored by `.gitignore`).

2. **Commit `cosign.pub` to the repository root:**

   ```bash
   git add cosign.pub
   git commit -m "Add cosign public signing key"
   ```

3. **Add `SIGNING_SECRET` to GitHub Actions:**
   - Open your GitHub repository -> **Settings** -> **Secrets and variables** -> **Actions** -> **New repository secret**.
   - Name: `SIGNING_SECRET`
   - Value: the full contents of `cosign.key`.

4. **Publish GHCR package visibility as Public:**
   - After the first successful CI run pushes `ghcr.io/<your-github-user>/sol-os`, open the package settings on GitHub (**Package settings -> Change visibility -> Public**) so target BC-250 systems and ISO workflows can pull signed images without authentication tokens.

---

## 4. Generating & Flashing `sol-os.iso`

### Option A: Generate `sol-os.iso` via GitHub Actions

1. Open the **Actions** tab in your GitHub repository and select **Build Sol OS** (`.github/workflows/build.yml`).
2. Click **Run workflow**:
   - **`build_iso`**: `true` (default)
   - **`image_tag`**: `latest` (or another published tag)
3. Once `Build & Sign Sol OS OCI Image` and `Generate Bootable sol-os.iso` complete, download the **`sol-os-iso`** artifact (retained for 7 days).
4. Extract the artifact archive and verify the SHA-256 checksum:

   ```bash
   sha256sum -c sol-os.iso.sha256
   ```

### Option B: Build & Generate Locally (`./build-local.sh`)

Validate YAML syntax and scripts locally (does not require `bluebuild` or `podman`):

```bash
./build-local.sh --validate-only
```

Build the OCI image locally and package `./iso-output/sol-os.iso` (requires `bluebuild` and `podman` on Linux):

```bash
./build-local.sh --iso
```

You can also invoke `bluebuild generate-iso` directly against either the local recipe or a published GHCR image:

```bash
# From local recipe:
mkdir -p ./iso-output
sudo bluebuild generate-iso --output-dir ./iso-output --iso-name sol-os.iso recipe recipes/recipe.yml

# From published GHCR image:
mkdir -p ./iso-output
sudo bluebuild generate-iso --output-dir ./iso-output --iso-name sol-os.iso image ghcr.io/<your-github-user>/sol-os:latest
```

### Flashing to a USB Drive

- **GUI (Fedora Media Writer):**
  1. Launch **Fedora Media Writer**.
  2. Choose **Select .iso file** and pick `iso-output/sol-os.iso`.
  3. Select your USB flash drive and write the image.

- **CLI (`dd`):**
  1. Identify the USB drive device node with `lsblk` (use the whole disk such as `/dev/sdX`, never a partition like `/dev/sdX1`).
  2. Flash and flush writes synchronously:

     ```bash
     sudo dd if=iso-output/sol-os.iso of=/dev/sdX bs=4M status=progress oflag=sync
     ```

---

## 5. Rebasing an Existing Bazzite Install onto Sol OS

If your BC-250 already runs `bazzite-deck`, you can rebase directly onto Sol OS in two stages so `cosign.pub` is trusted before enforcing signature verification.

> **Important `kargs` Note (`rpm-ostree` vs `bootc`):** BlueBuild's `kargs` module installs `/usr/lib/bootc/kargs.d/` drop-ins, which are applied automatically on fresh `sol-os.iso` installs and via `bootc switch` / `bootc upgrade`. However, `rpm-ostree rebase` does **not** automatically merge `/usr/lib/bootc/kargs.d/` drop-ins, so include the `rpm-ostree kargs --append-if-missing` step below when rebasing with `rpm-ostree`.

### Step 1: Initial Unsigned Rebase

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/<your-github-user>/sol-os:latest
systemctl reboot
```

### Step 2: Reboot, Switch to the Signed Image, and Ensure Kernel Arguments

Once booted into Sol OS (which now carries your `/etc/pki/containers` policy and `cosign.pub`), rebase to the signed reference and append `amdgpu.ppfeaturemask=0xffffffff` if missing:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/<your-github-user>/sol-os:latest
sudo rpm-ostree kargs --append-if-missing=amdgpu.ppfeaturemask=0xffffffff
systemctl reboot
```

> **`bootc` Alternative:** On systems managed with `bootc`, `bootc switch` applies `/usr/lib/bootc/kargs.d/` automatically:
> ```bash
> sudo bootc switch ghcr.io/<your-github-user>/sol-os:latest
> ```
> After rebooting into Sol OS (with the signing policy installed), subsequent `sudo bootc upgrade` runs verify signatures and apply image `kargs` automatically; to enforce signature verification immediately during a switch, pass `--enforce-container-sigpolicy`.

### Step 3: Verify `kargs` & BC-250 GPU Governor

After rebooting into the signed deployment, confirm the hardware kernel parameters and SMU governor are active:

```bash
rpm-ostree kargs
# Expected output includes: amdgpu.ppfeaturemask=0xffffffff

systemctl status cyan-skillfish-governor-smu.service
# Expected: active (running)
```

---

## 6. HelixSR Upscaling in Steam Game Mode (RDNA 2 Packed FP16)

Sol OS pre-stages **HelixSR** (tuned for RDNA 2 `GFX1013` packed FP16 execution) into the OS image so upscaling works without manual installer hunting.

### First-Boot Provisioning

- On your first graphical login, the systemd user unit `sol-helixsr-setup.service` automatically provisions HelixSR components and Decky integration for your user account.
- Once complete, it writes the marker file:

  ```text
  ~/.config/sol-helixsr-installed
  ```

### Toggling Upscaling Per Game in Steam Game Mode

1. Launch any supported game in **Steam Game Mode**.
2. Press the **Quick Access Menu (`...`)** button (or `Ctrl+2` on a keyboard).
3. Navigate to **Decky** -> **HelixSR Manager**.
4. Toggle **DLSS 3.7 (CNN Preset E)** or **HLX FSR 4** per game according to your visual and framerate target.

### Managing & Updating HelixSR (`helixsr-update`)

Use the built-in `helixsr-update` CLI (available in `/usr/local/bin/helixsr-update`) to inspect, update, or repair your user HelixSR installation:

```bash
helixsr-update                     # Update Decky Loader, HelixSR Manager plugin, and HelixSR core assets
helixsr-update --check             # Compare installed/staged versions against latest GitHub releases
helixsr-update --plugin-only       # Update only the HelixSR Manager plugin and restart plugin_loader
helixsr-update --decky-only        # Update only Decky Loader (PluginLoader) and restart plugin_loader
helixsr-update --reinstall-staged  # Restore/re-apply the offline OS-staged payloads via sol-helixsr-setup --force
```

### RDNA 2 Safeguard: Do NOT Stack `lsfg-vk` with HelixSR

> **WARNING:** Do **not** stack `lsfg-vk` frame-generation launch options simultaneously with **HelixSR** on the BC-250 (`GFX1013` / RDNA 2). Running both Vulkan swapchain layers at the same time causes swapchain contention, severe frame-pacing jitter, and potential GPU stalls. Use **either** HelixSR **or** `lsfg-vk` per title — never both together.

---

## 7. Safe GPU SMU Governor Tuning (`/etc/cyan-skillfish-governor-smu/config.toml`)

The BC-250 GPU frequency and voltage curve is controlled dynamically by `cyan-skillfish-governor-smu.service` reading `/etc/cyan-skillfish-governor-smu/config.toml`.

### Default Conservative Profile

Sol OS ships conservative defaults validated for stability across varied BC-250 silicon bins:

- **Frequency ceiling:** `2000` MHz
- **Safe voltage floor:** `950–1000` mV across three `[[safe-points]]`:
  - `1000` MHz @ `950` mV
  - `1500` MHz @ `975` mV
  - `2000` MHz @ `1000` mV
- **Thermal protection:** Throttling begins at **`85 °C`** (`throttling = 85`) and recovers at **`80 °C`** (`throttling_recovery = 80`).

### Safe Step-by-Step Tuning Workflow

1. **Back up the working configuration** before making edits:

   ```bash
   sudo cp /etc/cyan-skillfish-governor-smu/config.toml /etc/cyan-skillfish-governor-smu/config.toml.bak
   ```

2. **Adjust `/etc/cyan-skillfish-governor-smu/config.toml` incrementally:**
   - Change frequencies by **`25–50` MHz** or voltages by **`10–15` mV** per test pass.
   - Keep the lowest safe-point floor at or above `950` mV unless you have stress-tested transient shader spikes on your specific board.

3. **Restart the governor service to apply changes:**

   ```bash
   sudo systemctl restart cyan-skillfish-governor-smu.service
   systemctl status cyan-skillfish-governor-smu.service
   ```

4. **Validate stability under sustained load:**
   - Monitor GPU clocks and utilization with **`radeontop`**:

     ```bash
     radeontop
     ```

   - Check board and APU sensor temperatures with **`sensors`** (`lm_sensors`):

     ```bash
     sensors
     ```

   - Enable **MangoHud** in-game (via Steam Game Mode Quick Access Performance overlay or `MANGOHUD=1`) to watch frametime consistency, GPU frequency, power draw, and temperature during demanding scenes.

### Hard-Lockup Recovery

If an overly aggressive frequency/voltage configuration triggers an immediate GPU freeze or lockup at boot:

1. **Boot into a recovery state from GRUB:**
   - Power-cycle the BC-250 and hold **`Shift`** or tap **`Esc`** during early boot to display the **GRUB** menu.
   - Either select the **previous OSTree deployment** (if the regression followed an update), **or** press `e` on the current entry and append `systemd.mask=cyan-skillfish-governor-smu.service` (or `systemd.unit=multi-user.target`) to the `linux` kernel line, then press `Ctrl+X` / `F10` to boot.

2. **Restore the conservative configuration:**

   ```bash
   sudo systemctl stop cyan-skillfish-governor-smu.service
   sudo cp /etc/cyan-skillfish-governor-smu/config.toml.bak /etc/cyan-skillfish-governor-smu/config.toml
   sudo systemctl start cyan-skillfish-governor-smu.service
   ```

3. Reboot normally (`systemctl reboot`) once the service starts cleanly and temperatures/clocks read normally.

---

## 8. Sol Eclipse Theme (`sol-eclipse` / `org.sol-os.eclipse`)

Sol OS bakes the **Sol Eclipse** obsidian-and-gold visual theme directly into the OS image across early boot, Steam Game Mode, and KDE Plasma Desktop Mode:

- **Early Boot Splash (Plymouth):** `sol-eclipse` two-step theme (`/usr/share/plymouth/themes/sol-eclipse/`) baked into `initramfs` with centered solar eclipse, `SOL startup` typography, and golden ring spinner.
- **Steam Game Mode Startup & CSS Loader:** `sol_startup.webm` (1080p VP9 startup animation provisioned to `~/.local/share/Steam/config/uioverrides/movies/deck_startup.webm`) and the `Sol-Eclipse` CSS Loader theme staged into `~/homebrew/themes/Sol-Eclipse/` (enable **Sol Eclipse** inside Decky's **CSS Loader** plugin if installed).
- **KDE Plasma 6 Global Theme (`org.sol-os.eclipse`):** Solar Eclipse 2560×1440 wallpaper (`/usr/share/wallpapers/SolEclipse/`), `SolEclipse.colors` obsidian/gold palette, `SolEclipse` plasma style, QML login splash (`Splash.qml`), and desktop layout featuring a slim top bar (`Sol OS` launcher, system tray, clock), floating bottom dock, and desktop system/media widgets.
- **Re-apply or Reset Theme (`sol-theme-apply`):**
  ```bash
  sol-theme-apply                 # Apply/repair theme defaults, Steam startup movie, and CSS theme
  sol-theme-apply --force         # Re-apply even if ~/.config/sol-theme-applied exists
  sol-theme-apply --reset-layout  # Re-apply Plasma Global Theme and reset panels/dock/widgets to Sol Eclipse defaults
  ```
