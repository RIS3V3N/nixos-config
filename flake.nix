{
  description = "dom's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Packages that are not (yet) in the stable channel, e.g. hyprmoncfg.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      nixos-hardware,
      pre-commit-hooks,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      pre-commit-check = pre-commit-hooks.lib.${system}.run {
        src = ./.;
        hooks.nixfmt-rfc-style.enable = true;
      };
    in
    {
      formatter.${system} = pkgs.nixfmt-tree;

      checks.${system}.pre-commit-check = pre-commit-check;

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.nixfmt-rfc-style ];
        shellHook = pre-commit-check.shellHook;
      };

      nixosConfigurations.nixhorse = nixpkgs.lib.nixosSystem {
        inherit system;

        modules = [
          ./hosts/nixhorse/configuration.nix
          home-manager.nixosModules.home-manager
          # Cherry-pick single packages from nixpkgs-unstable as `pkgs.unstable.<name>`.
          {
            nixpkgs.overlays = [
              (final: prev: {
                unstable = import nixpkgs-unstable {
                  inherit (prev.stdenv.hostPlatform) system;
                  config.allowUnfree = true;
                };
              })
            ];
          }
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.users.dom = import ./home/dom.nix;
          }
        ];
      };
    };
}
