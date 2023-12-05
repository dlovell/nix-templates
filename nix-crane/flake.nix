# From https://github.com/litchipi/nix-build-templates/blob/6e4961dc56a9bbfa3acf316d81861f5bd1ea37ca/rust/maturin.nix
# See also https://discourse.nixos.org/t/pyo3-maturin-python-native-dependency-management-vs-nixpkgs/21739/2
{
  # Build Pyo3 package
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, flake-utils, crane, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ rust-overlay.overlays.default ];
      };

      rustVersion = "1.70.0";
      cargoToml = ./Cargo.toml;
      src = ./.;

      craneLib = (crane.mkLib pkgs).overrideToolchain pkgs.rust-bin.stable.${rustVersion}.default;
      my-crate = craneLib.buildPackage {
        src = craneLib.cleanCargoSource (craneLib.path src);
        # pname = (builtins.fromTOML (builtins.readFile cargoToml)).lib.name;
        inherit (craneLib.crateNameFromCargoToml { inherit cargoToml; }) version pname;
      };
      cargo-script = pkgs.writeShellScriptBin "cargo-script" ''
        set -xeu
        ${pkgs.cargo}/bin/cargo "''${@}"
      '';
      cargo-update-script = pkgs.writeShellScriptBin "cargo-update-script" ''
        set -xeu
        ${pkgs.cargo}/bin/cargo update "''${@}"
      '';
      cargo-build-script = pkgs.writeShellScriptBin "cargo-build-script" ''
        set -xeu
        ${pkgs.cargo}/bin/cargo build "''${@}"
      '';
    in rec {
      packages = {
        default = my-crate;
      };
      devShells = rec {
        rust = pkgs.mkShell {
          name = "rust-env";
          inherit src;
          nativeBuildInputs = with pkgs; [
            pkg-config
            rust-analyzer
            rust-bin.stable.${rustVersion}.default
          ];
        };
        default = rust;
      };
      apps = rec {
        default = flake-utils.lib.mkApp {
          drv = my-crate;
        };
        cargo = flake-utils.lib.mkApp {
          drv = cargo-script;
        };
        cargo-update = flake-utils.lib.mkApp {
          drv = cargo-update-script;
        };
        cargo-build = flake-utils.lib.mkApp {
          drv = cargo-build-script;
        };
      };
    });
}
