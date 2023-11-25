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

      pythonVersion = "310";
      rustVersion = "1.70.0";
      cargoToml = ./Cargo.toml;
      src = ./.;
      # `maturin build` prints the wheelName
      wheelTail = "cp38-abi3-linux_x86_64";

      python = pkgs.${"python" + pythonVersion};
      wheelName = "${commonArgs.pname}-${commonArgs.version}-${wheelTail}.whl";
      craneLib = (crane.mkLib pkgs).overrideToolchain pkgs.rust-bin.stable.${rustVersion}.default;

      pythonFilter = path: _type: builtins.match ".*py$" path != null;
      pythonOrCargo = path: type:
        (pythonFilter path type) || (craneLib.filterCargoSources path type);

      commonArgs = {
        pname = (builtins.fromTOML (builtins.readFile cargoToml)).lib.name;
        inherit (craneLib.crateNameFromCargoToml { inherit cargoToml; }) version;
      };
      crateWheel = (craneLib.buildPackage (commonArgs // {
        src = pkgs.lib.cleanSourceWith {
          src = craneLib.path src;
          filter = pythonOrCargo;
        };
        nativeBuildInputs = [ python ];
      })).overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.maturin ];
        buildPhase = old.buildPhase + ''
          maturin build --offline --target-dir target
        '';
        installPhase = old.installPhase + ''
          cp target/wheels/${wheelName} $out/
        '';
      });
      cargo-update-script = pkgs.writeShellScriptBin "cargo-update-script" ''
        set -xeu
        ${pkgs.cargo}/bin/cargo update
      '';
      maturin-init-script = pkgs.writeShellScriptBin "maturin-init" ''
        set -xeu
        ${pkgs.maturin}/bin/maturin init "''${@}"
        ${pkgs.cargo}/bin/cargo update
      '';
      maturin-init-pyo3-script = pkgs.writeShellScriptBin "maturin-init-pyo3" ''
        set -xeu
        ${pkgs.maturin}/bin/maturin init --bindings pyo3 "''${@}"
        ${pkgs.cargo}/bin/cargo update
      '';
    in rec {
      packages = {
        default = crateWheel;
        pythonEnv = (python.withPackages (ps: [
          (lib.pythonPackage ps)
          ps.ipython
        ])).override (_: { ignoreCollisions = true; });
      };
      lib = {
        pythonPackage = ps:
          ps.buildPythonPackage (commonArgs // rec {
            format = "wheel";
            src = "${crateWheel}/${wheelName}";
            doCheck = false;
            pythonImportsCheck = [ commonArgs.pname ];
          });
        };
      devShells = rec {
        rust = pkgs.mkShell {
          name = "rust-env";
          inherit src;
          nativeBuildInputs = with pkgs; [
            pkg-config
            rust-analyzer
            maturin
            maturin-init-script
            maturin-init-pyo3-script
            rust-bin.stable.${rustVersion}.default
          ];
        };
        python = pkgs.mkShell {
          name = "python-env";
          inherit src;
          nativeBuildInputs = [ self.packages.${system}.pythonEnv ];
        };
        default = python;
      };
      apps = rec {
        ipython = flake-utils.lib.mkApp {
          drv = packages.pythonEnv;
          name = "ipython";
        };
        maturin-init = flake-utils.lib.mkApp {
          drv = maturin-init-script;
        };
        maturin-init-pyo3 = flake-utils.lib.mkApp {
          drv = maturin-init-pyo3-script;
        };
        cargo-update = flake-utils.lib.mkApp {
          drv = cargo-update-script;
        };
        default = ipython;
      };
    });
}
