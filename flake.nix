{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-compat.url = "github:nix-community/flake-compat";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      devices = import ./devices.nix;
      eachDefaultSystem =
        f:
        builtins.zipAttrsWith (_: lib.listToAttrs) (
          map (
            system: builtins.mapAttrs (_: lib.nameValuePair system) (f system)
          ) lib.systems.flakeExposed
        );
    in
    {
      overlays = rec {
        default = x1e;
        x1e = import ./packages/overlay.nix;
      };

      nixosModules = rec {
        default = x1e;
        x1e =
          { lib, pkgs, ... }:
          {
            # TODO: expose these modules on their own?
            imports = [
              ./modules/x1e80100.nix
              ./modules/el2.nix
            ];
            config = {
              nixpkgs.overlays = [
                self.overlays.default
              ];
            };
          };
      }
      // builtins.mapAttrs (device: {
        imports = [ self.nixosModules.default ];
        hardware.${device}.enable = true;
      }) devices;

      # Set nixosConfigurations to the non-cross systems.
      nixosConfigurations = self.nixosConfigurationsForBuildSystem.aarch64-linux;
    }

    # Generate attributes for each build system
    // eachDefaultSystem (
      buildSystem:
      let
        pkgs-unpatched = nixpkgs.legacyPackages.${buildSystem};

        nixpkgs-patched =
          (pkgs-unpatched.applyPatches {
            name = "nixpkgs-patched";
            src = nixpkgs;
            patches = [
              (pkgs-unpatched.fetchpatch {
                # nixos/iso-image: add devicetree support
                # https://github.com/NixOS/nixpkgs/pull/396334
                url = "https://github.com/NixOS/nixpkgs/commit/de1fdb6310af8f70c98746ba4550dc2799a03621.patch";
                hash = "sha256-brqJxblmqWFAk8JgxmxXeHoiaWiQtsCsOzht/WlH5eE=";
              })
              ./nixpkgs-efi-shell.patch
            ];
          }).overrideAttrs
            { allowSubstitutes = true; };

        pkgs-cross = import nixpkgs-patched {
          overlays = [
            self.overlays.default
            (final: prev: {
              grub2 = prev.grub2.overrideAttrs (old: {
                patches = (old.patches or [ ]) ++ [
                  # Limit grub to 4GB RAM, needed to boot T14s 64GB variant
                  (final.fetchpatch {
                    url = "https://lore.kernel.org/grub-devel/20250407183002.601690-1-tobias.heider@canonical.com/raw";
                    # See: https://github.com/NixOS/nixpkgs/issues/400905
                    decode = "(grep '^[a-zA-Z0-9+/=]\\+$' | base64 -d)";
                    hash = "sha256-BMGek9GNiRpSNpP1o06pprPoIVW+ZNZwVYjW4egp4Ig=";
                  })
                ];
              });
            })
          ];
          localSystem.system = buildSystem;
          crossSystem.system = "aarch64-linux";
          allowUnsupportedSystem = true;
        };

        treefmtEval =
          let
            treefmt-nix = import (
              pkgs-unpatched.fetchFromGitHub {
                owner = "numtide";
                repo = "treefmt-nix";
                rev = "0ce9d149d99bc383d1f2d85f31f6ebd146e46085";
                hash = "sha256-s4DalCDepD22jtKL5Nw6f4LP5UwoMcPzPZgHWjAfqbQ=";
              }
            );
          in
          (treefmt-nix.evalModule pkgs-unpatched {
            programs.nixfmt.enable = true;
            settings.on-unmatched = "info";
            programs.mdformat = {
              enable = true;
              package = pkgs-unpatched.mdformat.withPlugins (p: [ p.mdformat-gfm ]);
            };
          });

        deviceISO =
          device:
          lib.nixosSystem {
            modules = [
              "${nixpkgs-patched}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ./iso.nix
              self.nixosModules.default
              {
                nixpkgs.pkgs = pkgs-cross;
                hardware.${device}.enable = true;
              }
            ];
          };

        deviceSystem =
          device:
          lib.nixosSystem {
            modules = [
              ./examples/flake-based-config/configuration.nix
              self.nixosModules.default
              {
                nixpkgs.pkgs = pkgs-cross;
                hardware.${device}.enable = true;
              }
            ];
          };
      in
      {
        # This is a non-standard attribute, but the default
        # `nixosConfigurations` attribute was not designed with cross compiled
        # nixos configurations in mind, and `nix flake check` would complain if
        # we used it.
        nixosConfigurationsForBuildSystem = builtins.listToAttrs (
          builtins.concatLists (
            lib.mapAttrsToList (device: _: [
              (lib.nameValuePair device (deviceSystem device))
              (lib.nameValuePair "${device}-iso" (deviceISO device))
            ]) devices
          )
        );

        packages = {
          # Convenience aliases
          iso = self.packages.${buildSystem}.lenovo-yoga-slim7x-iso;
          kernel = pkgs-cross.linuxPackages_x1e.kernel;
          inherit (pkgs-cross) denali-firmware slbounce;
        }
        // lib.mapAttrs' (
          device: _: lib.nameValuePair "${device}-iso" (deviceISO device).config.system.build.isoImage
        ) devices;

        formatter = treefmtEval.config.build.wrapper;
        checks = {
          treefmt = treefmtEval.config.build.check self;
        };
      }
    );
}
