{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # zls-overlay.url = "github:zigtools/zls/edd8f2264ea45f7370bac4aba809bc179d96627e";
    esp-idf.url = "github:mirrexagon/nixpkgs-esp-dev";
  };

  outputs = { self, nixpkgs, flake-utils, esp-idf, ... }: # zls-overlay, 
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ esp-idf.overlays.default ];
        };

        # Determine architecture-specific properties
        platformSrc = if system == "x86_64-linux" then
          {
            url = "https://github.com/kassane/zig-espressif-bootstrap/releases/download/0.14.0-xtensa/zig-relsafe-x86_64-linux-musl-baseline.tar.xz";
            sha256 = "sha256-czEQX03pDNzoh9SGhWfs5miU7vK1md7sYCd3lHSLLCA=";
          }
        else if system == "aarch64-linux" then
          {
            url = "https://github.com/kassane/zig-espressif-bootstrap/releases/download/0.14.0-xtensa/zig-relsafe-aarch64-linux-musl-baseline.tar.xz";
            sha256 = "sha256-MUrTa7hI1Gx4vCM+0Tnu5D7agoUWzPb11pufIBptFCQ=";
          }
        else
          throw "Unsupported platform: ${system}";

        zigEsp = pkgs.stdenv.mkDerivation {
          pname = "zig-espressif-bootstrap";
          version = "0.14.0-xtensa";
          src = pkgs.fetchurl platformSrc;
          dontConfigure = true; dontBuild = true; dontFixup = true;
          installPhase = ''
            mkdir -p $out/{doc,bin,lib}
            cp -r doc/* $out/doc
            cp -r lib/* $out/lib
            cp zig $out/bin/zig
          '';
        };

      in
      {
        formatter = pkgs.nixpkgs-fmt;
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.bashInteractive

            zigEsp
            pkgs.zls

            pkgs.esp-idf-full
          ];
        };
      }
    );
}
