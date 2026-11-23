{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.smartconnect;
in
{
  options.services.smartconnect = {
    enable = lib.mkEnableOption "Smart Connect for Linux (Motorola phone link daemon)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.smartconnect-linux";
      description = "The smartconnect-linux package to install.";
    };

    deviceName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "Device name shown in Motorola Smart Connect on the phone.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 52020;
      description = "TCP port for the TLS WebSocket server (pairing and sessions).";
    };

    tokenTtl = lib.mkOption {
      type = lib.types.ints.positive;
      default = 180;
      description = "Pairing QR code token lifetime in seconds.";
    };

    enableHelpers = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether smartconnectd automatically spawns desktop helpers (mirror host,
        Cross Control, webcam, and phone-as-display) when requested by the phone.
        Disable (SMARTCONNECT_HELPERS=0) for tighter security on shared networks.
      '';
    };

    enableBluetoothWake = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Allow waking Smart Connect on the phone over Bluetooth LE while the app
        is in the background (requires hardware.bluetooth.enable = true).
      '';
    };

    lockCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional custom screen lock command for the phone's PC Lock tile.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra command-line arguments passed to smartconnectd.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the control port in the firewall. Prefer also setting
        firewallInterfaces to restrict access to your trusted LAN/Wi-Fi interface.
      '';
    };

    firewallInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "wlp3s0" ];
      description = ''
        Network interfaces on which to open Smart Connect firewall ports.
        When empty and openFirewall is true, ports are opened on all interfaces.
      '';
    };

    openFileShareFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open fileSharePort in the firewall for PC-to-phone file sharing (smartconnect-files serve).";
    };

    fileSharePort = lib.mkOption {
      type = lib.types.port;
      default = 2049;
      description = "TCP port used by smartconnect-files serve.";
    };

    enableWebcamModule = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Load v4l2loopback so the phone camera appears as a standard V4L2 webcam.";
    };

    enableVkms = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Load the vkms kernel module (only needed for Extend mode on niri).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # mDNS discovery (_readyformdns._tcp)
    services.avahi = {
      enable = lib.mkDefault true;
      openFirewall = lib.mkDefault true;

      # O NixOS desabilita publicação por padrão (disable-publishing=yes e
      # disable-user-service-publishing=yes). Sem isso o avahi-publish falha
      # com "Failed to create entry group: Not permitted" e o celular não
      # enxerga o PC pelo botão Connect.
      settings.publish = {
        "disable-publishing" = false;
        "disable-user-service-publishing" = false;
      };
    };

    # A policy D-Bus do avahi (avahi-dbus.conf) referencia o grupo "netdev";
    # o dbus-broker descarta o arquivo inteiro se o grupo não existir, e o
    # cliente avahi perde permissão de falar com o daemon.
    users.groups.netdev = lib.mkDefault { };

    # Firewall rules
    networking.firewall =
      let
        tcpPorts =
          lib.optional cfg.openFirewall cfg.port
          ++ lib.optional cfg.openFileShareFirewall cfg.fileSharePort;
      in
      lib.mkIf (tcpPorts != [ ]) (
        if cfg.firewallInterfaces == [ ] then
          { allowedTCPPorts = tcpPorts; }
        else
          {
            interfaces = lib.genAttrs cfg.firewallInterfaces (_: {
              allowedTCPPorts = tcpPorts;
            });
          }
      );

    # Optional kernel modules
    boot.extraModulePackages = lib.mkIf cfg.enableWebcamModule [
      config.boot.kernelPackages.v4l2loopback
    ];

    boot.kernelModules =
      lib.optional cfg.enableWebcamModule "v4l2loopback"
      ++ lib.optional cfg.enableVkms "vkms";

    boot.extraModprobeConfig = lib.mkIf cfg.enableWebcamModule ''
      options v4l2loopback devices=1 video_nr=10 card_label="Phone Camera" exclusive_caps=1
    '';

    # User daemon managed by NixOS
    systemd.user.services.smartconnectd = {
      description = "Smart Connect for Linux (Motorola phone link daemon)";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];

      environment = {
        RUST_LOG = "info";
      }
      // lib.optionalAttrs (!cfg.enableHelpers) {
        SMARTCONNECT_HELPERS = "0";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.escapeShellArgs (
          [
            "${cfg.package}/bin/smartconnectd"
            "--port"
            (toString cfg.port)
            "--token-ttl"
            (toString cfg.tokenTtl)
            "--no-ble"
            "--name"
            cfg.deviceName
          ]
          ++ lib.optional (!cfg.enableBluetoothWake) "--no-ble-wake"
          ++ lib.optionals (cfg.lockCommand != null) [
            "--lock-command"
            cfg.lockCommand
          ]
          ++ cfg.extraArgs
        );
        Restart = "on-failure";
        RestartSec = 3;
      };
    };
  };
}
