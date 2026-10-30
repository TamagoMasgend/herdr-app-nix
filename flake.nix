{
  description = "Nix packaging for the Herdr desktop app (herdr-app) and its runtime, herdr-core";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/ac6b2166e7a9375683b8e98f860f273222337b16";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system} system);

      # callPackage against `final`, so herdr-app finds herdr-core.
      overlay = final: _prev: {
        herdr-core = final.callPackage ./pkgs/herdr-core.nix { };
        herdr-app = final.callPackage ./pkgs/herdr-app.nix { };
      };
    in
    {
      overlays.default = overlay;

      packages = forAllSystems (
        pkgs: _: rec {
          herdr-core = pkgs.callPackage ./pkgs/herdr-core.nix { };
          herdr-app = pkgs.callPackage ./pkgs/herdr-app.nix { inherit herdr-core; };
          default = herdr-app;
        }
      );

      checks = forAllSystems (
        pkgs: system:
        let
          inherit (self.packages.${system}) herdr-core herdr-app;
        in
        {
          inherit herdr-core herdr-app;

          herdr-app-cli = pkgs.runCommand "herdr-app-cli-check" { } ''
            ${herdr-app}/bin/herdr-app --version | grep -F "herdr-app ${herdr-app.version}"
            ${herdr-app}/bin/herdr-app --skill | grep -F "hc"
            # The patch that lets the app find this flake's core must survive
            # stripping and fixup.
            grep -qaF "${herdr-core}/bin" ${herdr-app}/bin/herdr-app
            touch $out
          '';
        }
      );

      formatter = forAllSystems (pkgs: _: pkgs.nixfmt);

      apps = forAllSystems (
        _pkgs: system:
        let
          inherit (self.packages.${system}) herdr-app herdr-core;
        in
        {
          default = {
            type = "app";
            program = "${herdr-app}/bin/herdr-app";
            meta.description = "Open the Herdr desktop app";
          };
          herdr-core = {
            type = "app";
            program = "${herdr-core}/bin/hc";
            meta.description = "Run the herdr-core CLI (hc)";
          };
        }
      );
    };
}
