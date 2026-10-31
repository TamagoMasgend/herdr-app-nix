# herdr-app-nix

Nix packaging for the [Herdr desktop app](https://herdr.dev/) (`herdr-app`) and its
runtime, [herdr-core](https://herdr.dev/core/) (`hc`), built from source.

Upstream distributes both through `curl … | sh` installers and release tarballs.
This flake builds the same versions from the tagged sources, with the fixes a
Nix build needs.

| Package | Version | Binary |
| --- | --- | --- |
| `herdr-app` (default) | 0.1.9 | `herdr-app` |
| `herdr-core` | 0.1.14 | `hc`, `herdr-core` |

The app needs a core of at least 0.1.11.

## Usage

Try it without installing anything:

```sh
nix run github:TamagoMasgend/herdr-app-nix
```

Add the input and overlay to your existing NixOS flake. This example imports
`./configuration.nix`; use your host's path and platform, and keep its existing
`system.stateVersion`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    herdr-app-nix.url = "github:TamagoMasgend/herdr-app-nix";
  };

  outputs = { nixpkgs, herdr-app-nix, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        ./configuration.nix
        ({ pkgs, ... }: {
          nixpkgs.hostPlatform = "x86_64-linux";
          nixpkgs.overlays = [ herdr-app-nix.overlays.default ];
          environment.systemPackages = [ pkgs.herdr-app pkgs.herdr-core ];
        })
      ];
    };
  };
}
```

Or straight from the flake's own package set:

```nix
environment.systemPackages = [
  herdr-app-nix.packages.${pkgs.stdenv.hostPlatform.system}.herdr-app
  herdr-app-nix.packages.${pkgs.stdenv.hostPlatform.system}.herdr-core
];
```

There is no NixOS or Home Manager module yet: both are user programs, started
from the desktop entry or the app itself.

## What the packaging changes

- **RUNPATH instead of `LD_LIBRARY_PATH`** for Vulkan, OpenGL and Wayland. The
  app starts `herdr-core`, which passes its environment on to every terminal,
  so a wrapper's `LD_LIBRARY_PATH` would leak into every shell.
- **`xdg-open` is absolute.** The app opens links and files with it, and a Nix
  desktop session may not have `xdg-open` on the app's `PATH`.
- **The app finds this flake's core** only after `core` in settings, `PATH`,
  the usual install directories and the login shell have failed — a core you
  installed yourself still wins.
- **`hc machine add` downloads the static release** instead of copying its own
  binary to a machine with the same OS and CPU. A Nix-built `hc` needs its
  `/nix/store` paths, which the other machine does not have.
- **`curl`, `sha256sum` and `bsdtar`** are pinned to their store paths, since
  `hc` uses them to fetch and verify releases for the machines it adds.
- **The settings screen says "Managed by nix"** instead of offering a git
  update (upstream: [herdr-app#136](https://github.com/herdrdev/herdr-app/issues/136)).

Upstream's test suites run as part of the build (`nix flake check`); four tests
are skipped: two install a core on another machine, which this packaging now
always downloads (no network in the sandbox), one reads element bounds only
debug builds record, and one races GPUI's test scheduler.

## Platforms

Linux only. `x86_64-linux` has been built and runtime-smoke-tested;
`aarch64-linux` evaluates, but has not been built or run here. Upstream also
builds macOS and Windows; these derivations are not adapted to those platforms.

The app draws with Vulkan (Mesa's software driver is enough) and needs a
desktop session.

## Notes

- Not an official package: upstream has no release here. The same two packages
  are proposed to nixpkgs as [NixOS/nixpkgs#581031](https://github.com/NixOS/nixpkgs/pull/581031);
  this repo is independent of that PR and can be deleted once it lands.
- Report packaging problems here, app and core bugs upstream:
  [herdr-app](https://github.com/herdrdev/herdr-app),
  [herdr-core](https://github.com/herdrdev/herdr-core).
- Pinned to nixpkgs `ac6b2166e7a9375683b8e98f860f273222337b16`.
- Both programs are Apache-2.0, as are the built binaries; their third-party
  notices are installed under `share/doc`.
