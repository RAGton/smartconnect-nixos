# NixOS

This fork adds native Nix/NixOS packaging (`flake.nix`, `default.nix`, `nix/package.nix`, and `nix/nixos-module.nix`) along with NixOS compatibility and security fixes.

## Requirements

- NixOS **25.05+** / `nixos-unstable` (requires Rust ≥ 1.88, GTK ≥ 4.18, libadwaita ≥ 1.7, and GStreamer ≥ 1.22).

## Quick start (Flakes)

Add the flake to your system `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    smartconnect-nixos = {
      url = "github:RAGton/smartconnect-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, smartconnect-nixos, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        smartconnect-nixos.nixosModules.default
        {
          # Optional: needed for Bluetooth LE background wake
          hardware.bluetooth.enable = true;

          services.smartconnect = {
            enable = true;
            deviceName = "NixOS-PC";
            openFirewall = true;
            # Strongly recommended: restrict TCP 52020 to your trusted LAN/Wi-Fi interface
            firewallInterfaces = [ "wlp0s20f3" ];
            # enableWebcamModule = true; # v4l2loopback for phone-as-webcam in all apps
            # enableVkms = true;         # vkms virtual output (only needed for Extend on niri)
            # enableHelpers = false;     # disables automatic helper spawning on phone requests
          };
        }
      ];
    };
  };
}
```

Or build/run directly without modifying your system config:

```sh
nix build github:RAGton/smartconnect-nixos
nix run github:RAGton/smartconnect-nixos
```

## Quick start (Classic `configuration.nix`)

Clone the repository and import `nix/nixos-module.nix`:

```nix
{
  imports = [
    ./hardware-configuration.nix
    /path/to/smartconnect-nixos/nix/nixos-module.nix
  ];

  hardware.bluetooth.enable = true;

  services.smartconnect = {
    enable = true;
    deviceName = "NixOS-PC";
    openFirewall = true;
    firewallInterfaces = [ "wlp0s20f3" ];
  };
}
```

Then rebuild:

```sh
sudo nixos-rebuild switch
```

## Optional package overrides

`nix/package.nix` exposes boolean flags for optional runtime helpers:

- `withFfmpeg` (default `true`): `ffmpeg-headless` for video thumbnails when sharing PC folders.
- `withNetworkManager` (default `true`): `nmcli` for the Hotspot tile.
- `withWvkbd` (default `false`): on-screen keyboard on wlroots/niri compositors.
- `withQuickshell` (default `false`): `qs` quick-reply popup window.

Example:

```nix
services.smartconnect.package =
  smartconnect-nixos.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    withWvkbd = true;
    withQuickshell = true;
  };
```

## NixOS-specific adjustments included in this fork

- **Binary wrapping without breaking `/proc/<pid>/comm` or KDE KWin:** real ELF binaries are installed in `$out/libexec/smartconnect-linux/` under their original names, wrapped into `$out/bin/` with `makeBinaryWrapper`, and `dev.smartconnect.Display.desktop` points `Exec=` at the real `libexec` executable so KWin trusts it for screencasting and input injection.
- **GStreamer plugins:** wraps `GST_PLUGIN_SYSTEM_PATH_1_0` using `lib.getLib` so `libnice`'s `libgstnice.so` (`nicesrc`/`nicesink`), PipeWire, and all required GStreamer plugins are resolved.
- **FUSE3 (`fusermount3`):** keeps `/run/wrappers/bin` ahead of unwrapped `fuse3` on `PATH` so NixOS's setuid `fusermount3` wrapper is used.
- **Icon themes:** `src/notifications.rs` searches `XDG_DATA_HOME` and `XDG_DATA_DIRS` instead of only `/usr/share/icons`.
- **Security hardening:**
  - `src/server.rs`: restricts fex `/websocket` and `/download` clipboard-image routes to the currently connected phone's IP and only while an offer is active.
  - `files/src/localfs.rs`: refuses symlinks in `read()` and `thumbnail()` (`symlink_metadata` + `is_file()`).
  - `nix/nixos-module.nix`: defaults `tokenTtl` to `180` seconds and supports per-interface firewall rules (`firewallInterfaces`).
