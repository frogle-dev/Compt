{
  description = "comp-ecs zig devenv";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";

    zig-overlay.url = "github:mitchellh/zig-overlay";

    zls-overlay.url = "github:zigtools/zls/0.17.0";
    zls-overlay.inputs.nixpkgs.follows = "nixpkgs";
    zls-overlay.inputs.zig-overlay.follows = "zig-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,

      zig-overlay,
      zls-overlay,
    }:

    utils.lib.eachDefaultSystem (
      system:

      let
        pkgs = import nixpkgs { inherit system; };

        zig = zig-overlay.packages.${system}."0.17.0";
        zls = zls-overlay.packages.${system}.zls;
      in
      {
        devShell = pkgs.mkShell {
          nativeBuildInputs = [
            zig
            zls
          ];
        };
      }
    );
}
