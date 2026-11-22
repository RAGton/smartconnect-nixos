{
  description = "Smart Connect for Linux — unofficial NixOS port for Motorola Smart Connect";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
            }
          )
        );
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          pkg = pkgs.callPackage ./nix/package.nix { };
        in
        {
          smartconnect-linux = pkg;
          default = pkg;
        }
      );

      overlays.default = final: _prev: {
        smartconnect-linux = final.callPackage ./nix/package.nix { };
      };

      nixosModules = {
        smartconnect = import ./nix/nixos-module.nix;
        default = self.nixosModules.smartconnect;
      };

      devShells = forAllSystems (
        pkgs:
        let
          pkg = self.packages.${pkgs.stdenv.hostPlatform.system}.smartconnect-linux;
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [ pkg ];
            packages = with pkgs; [
              cargo
              rustc
              rust-analyzer
              clippy
              rustfmt
              avahi
              wl-clipboard
              fuse3
              ffmpeg
              libxkbcommon
              gst_all_1.gstreamer
            ];
            GST_PLUGIN_SYSTEM_PATH_1_0 = pkgs.lib.makeSearchPath "lib/gstreamer-1.0" (
              map pkgs.lib.getLib (
                with pkgs.gst_all_1;
                [
                  gstreamer
                  gst-plugins-base
                  gst-plugins-good
                  gst-plugins-bad
                  gst-plugins-ugly
                  gst-libav
                  pkgs.libnice
                  pkgs.pipewire
                ]
              )
            );
          };
        }
      );
    };
}
