Sol OS — RDNA 2 (GFX1013 / AMD BC-250) HelixSR & Decky Loader Guide
=====================================================================

1. Overview: Packed FP16 Upscaling on RDNA 2
--------------------------------------------
Sol OS ships pre-staged support for Decky Loader and HelixSR so RDNA 2 GPUs
(including AMD BC-250 / GFX1013 and Steam Deck class APUs) can run neural
upscalers without native FP8 tensor hardware.

HelixSR executes DLSS 3.7 (CNN Preset E) and HLX FSR 4 models via optimized
packed FP16 compute shader paths suited to RDNA 2 architecture.

Immutable OS payloads are staged in:
  /usr/share/sol-os/helixsr/

User runtime installation lives in:
  ~/homebrew/services/PluginLoader
  ~/homebrew/plugins/HelixSR-Manager/
  ~/homebrew/data/HelixSR-Manager/staged/


2. Enabling DLSS 3.7 (CNN Preset E) & HLX FSR 4 in Steam Game Mode
------------------------------------------------------------------
On first user login, sol-helixsr-setup.service automatically provisions
~/homebrew, enables Steam CEF remote debugging (.cef-enable-remote-debugging),
and starts plugin_loader.service.

To configure upscaling per game in Steam Game Mode:
  1. Press the Quick Access button (...) to open the side menu.
  2. Open the Decky Loader tab (plug icon).
  3. Select "HelixSR Manager".
  4. Choose the target game from your Steam library list.
  5. Install/deploy HelixSR (native or OptiScaler path) for that game.
  6. Select your upscaler profile:
       - DLSS 3.7 (CNN Preset E): Recommended default on RDNA 2 for lower
         compute overhead, strong temporal stability, and cooler GPU power draw.
       - HLX FSR 4: Higher neural model quality; heavier on RDNA 2 shader/FP16
         throughput (best suited to titles with sufficient GPU headroom).
  7. Launch the game and verify in the HelixSR Manager status/overlay readout.


3. CRITICAL RDNA 2 SAFEGUARD: Do NOT Stack lsfg-vk with HelixSR
---------------------------------------------------------------
NEVER combine lsfg-vk frame generation launch options with HelixSR upscaling
on RDNA 2 (GFX1013 / AMD BC-250).

Why:
  - Both HelixSR neural upscaling and lsfg-vk optical-flow frame generation
    compete aggressively for RDNA 2 async compute queues and memory bandwidth.
  - Stacking them causes severe frame-pacing judder, Vulkan swapchain stalls,
    and GPU compute queue contention.

Rule of thumb:
  - Use HelixSR upscaling OR lsfg-vk frame generation per game — never both at
    the same time. If enabling HelixSR for a game, remove any lsfg-vk launch
    options from that game's Steam Properties -> Launch Options.


4. Updating & Repairing via helixsr-update
------------------------------------------
Run updates as your regular desktop/gaming user (do NOT run as root/sudo):

  helixsr-update                    Update Decky Loader, HelixSR Manager, and
                                    staged HelixSR core cache, then restart
                                    plugin_loader.
  helixsr-update --check            Compare installed/staged versions against
                                    latest GitHub releases (read-only).
  helixsr-update --plugin-only      Update only the HelixSR Manager Decky plugin.
  helixsr-update --decky-only       Update only Decky Loader PluginLoader.
  helixsr-update --reinstall-staged Re-apply the immutable OS-staged payloads
                                    (runs sol-helixsr-setup --force).
  helixsr-update --help             Show usage and RDNA 2 compatibility notes.


5. Quick Troubleshooting
------------------------
  - Check provisioning state:
      cat ~/.config/sol-helixsr-installed
  - Check user Decky Loader service (or system plugin_loader if installed):
      systemctl --user status plugin_loader.service
      journalctl --user -u plugin_loader.service -n 50 --no-pager
  - Check first-boot setup unit:
      systemctl --user status sol-helixsr-setup.service
