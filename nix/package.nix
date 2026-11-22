{
  lib,
  rustPlatform,
  pkg-config,
  wrapGAppsHook4,
  makeBinaryWrapper,
  dbus,
  wayland,
  gtk4,
  libadwaita,
  gst_all_1,
  libnice,
  pipewire,
  avahi,
  wl-clipboard,
  iproute2,
  glib,
  libxkbcommon,
  libnotify,
  fuse3,
  ffmpeg-headless,
  networkmanager,
  wvkbd,
  quickshell,
  withFfmpeg ? true,
  withNetworkManager ? true,
  withWvkbd ? false,
  withQuickshell ? false,
}:

let
  gstPlugins = with gst_all_1; [
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-plugins-ugly
    gst-libav
  ];

  gstPluginPath = lib.makeSearchPath "lib/gstreamer-1.0" (
    map lib.getLib (
      gstPlugins ++ [
        libnice
        pipewire
      ]
    )
  );

  runtimeBins =
    [
      avahi
      wl-clipboard
      iproute2
      glib
      libxkbcommon
      libnotify
    ]
    ++ lib.optional withFfmpeg ffmpeg-headless
    ++ lib.optional withNetworkManager networkmanager
    ++ lib.optional withWvkbd wvkbd
    ++ lib.optional withQuickshell quickshell;

  runtimePath = lib.makeBinPath runtimeBins;

  src = lib.fileset.toSource {
    root = ./..;
    fileset = lib.fileset.unions [
      ../Cargo.toml
      ../Cargo.lock
      ../LICENSE
      ../src
      ../mirror
      ../crosscontrol
      ../display
      ../webcam
      ../files
      ../fex
      ../gui
      ../desktop
      ../tests
      ../packaging
      ../noctalia-plugin
    ];
  };
in
rustPlatform.buildRustPackage {
  pname = "smartconnect-linux";
  version = "0.1.0";

  inherit src;

  cargoLock = {
    lockFile = ../Cargo.lock;
  };

  cargoBuildFlags = [ "--workspace" ];
  cargoTestFlags = [ "--workspace" ];

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
    makeBinaryWrapper
  ];

  buildInputs =
    [
      dbus
      wayland
      gtk4
      libadwaita
      libnice
      pipewire
    ]
    ++ gstPlugins;

  # We wrap each binary manually with makeBinaryWrapper in postFixup (after
  # wrapGAppsHook4 populates gappsWrapperArgs in preFixup) while keeping the real
  # ELF binaries under $out/libexec/smartconnect-linux/ with their original
  # filenames so /proc/<pid>/comm (used by smartconnect-gui) and KDE KWin's
  # absolute Exec= trust check on smartconnect-display both continue to match.
  dontWrapGApps = true;

  postInstall = ''
    libexec="$out/libexec/smartconnect-linux"
    mkdir -p "$libexec"

    bins=(
      smartconnectd
      smartconnect-mirror
      smartconnect-crosscontrol
      smartconnect-display
      smartconnect-webcam
      smartconnect-files
      smartconnect-fex
      smartconnect-gui
    )

    for b in "''${bins[@]}"; do
      mv "$out/bin/$b" "$libexec/$b"
    done

    # Systemd user unit
    install -d "$out/lib/systemd/user"
    sed \
      -e "s|%h/\\.local/bin/|$out/bin/|g" \
      -e "s|%h/\\.local/share/doc/smartconnect-linux/|$out/share/doc/smartconnect-linux/|g" \
      packaging/systemd/smartconnectd.service \
      > "$out/lib/systemd/user/smartconnectd.service"
    chmod 644 "$out/lib/systemd/user/smartconnectd.service"

    # Desktop entries and icon
    install -d "$out/share/applications"
    sed "s|^Exec=smartconnect-gui|Exec=$out/bin/smartconnect-gui|" \
      packaging/dev.smartconnect.Linux.desktop \
      > "$out/share/applications/dev.smartconnect.Linux.desktop"
    # KWin matches Exec= against the actual executable path (/proc/<pid>/exe).
    sed "s|^Exec=smartconnect-display|Exec=$libexec/smartconnect-display|" \
      packaging/dev.smartconnect.Display.desktop \
      > "$out/share/applications/dev.smartconnect.Display.desktop"
    chmod 644 "$out/share/applications/"*.desktop

    install -Dm644 packaging/dev.smartconnect.Linux.svg \
      "$out/share/icons/hicolor/scalable/apps/dev.smartconnect.Linux.svg"

    # Noctalia Shell plugin
    install -d "$out/share/smartconnect-linux/noctalia-plugin/smart-connect"
    cp -r noctalia-plugin/smart-connect/. \
      "$out/share/smartconnect-linux/noctalia-plugin/smart-connect/"
    rm -f "$out/share/smartconnect-linux/noctalia-plugin/smart-connect/settings.json"

    # Documentation and license
    install -Dm644 packaging/README.md "$out/share/doc/smartconnect-linux/README.md"
    install -Dm644 LICENSE "$out/share/doc/smartconnect-linux/LICENSE"
  '';

  postFixup = ''
    libexec="$out/libexec/smartconnect-linux"

    helperEnvArgs=(
      --set-default SMARTCONNECT_MIRROR_BIN "$out/bin/smartconnect-mirror"
      --set-default SMARTCONNECT_CROSSCONTROL_BIN "$out/bin/smartconnect-crosscontrol"
      --set-default SMARTCONNECT_DISPLAY_BIN "$out/bin/smartconnect-display"
      --set-default SMARTCONNECT_WEBCAM_BIN "$out/bin/smartconnect-webcam"
      --set-default SMARTCONNECT_FILES_BIN "$out/bin/smartconnect-files"
      --set-default SMARTCONNECT_SMARTCONNECTD_BIN "$out/bin/smartconnectd"
    )

    # Keep /run/wrappers/bin ahead of unwrapped fuse3 so NixOS's setuid fusermount3 is used.
    pathArgs=(
      --prefix PATH : "${runtimePath}"
      --suffix PATH : "/run/wrappers/bin:${lib.makeBinPath [ fuse3 ]}"
    )

    gstArgs=(
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${gstPluginPath}"
    )

    makeBinaryWrapper "$libexec/smartconnectd" "$out/bin/smartconnectd" \
      "''${helperEnvArgs[@]}" \
      "''${gstArgs[@]}" \
      "''${pathArgs[@]}"

    makeBinaryWrapper "$libexec/smartconnect-gui" "$out/bin/smartconnect-gui" \
      "''${gappsWrapperArgs[@]}" \
      "''${helperEnvArgs[@]}" \
      "''${pathArgs[@]}"

    for b in smartconnect-mirror smartconnect-display smartconnect-webcam; do
      makeBinaryWrapper "$libexec/$b" "$out/bin/$b" \
        "''${gstArgs[@]}" \
        "''${pathArgs[@]}"
    done

    for b in smartconnect-crosscontrol smartconnect-files smartconnect-fex; do
      makeBinaryWrapper "$libexec/$b" "$out/bin/$b" \
        "''${pathArgs[@]}"
    done
  '';

  meta = with lib; {
    description = "Unofficial Linux peer for the Motorola Smart Connect phone app";
    homepage = "https://github.com/rudrahnpatel/smartconnect-linux";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "smartconnect-gui";
  };
}
