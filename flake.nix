{
  description = "Swhkd devel";

  inputs = { nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable"; };

  outputs = { self, nixpkgs, ... }:
    let
      pkgsFor = system:
        import nixpkgs {
          inherit system;
          overlays = [ ];
        };

      targetSystems = [ "aarch64-linux" "x86_64-linux" ];
    in {
      packages = nixpkgs.lib.genAttrs targetSystems (system:
        let
          pkgs = pkgsFor system;
          mkSwhkd = { withRfkill ? true }:  pkgs.rustPlatform.buildRustPackage {
            pname = "swhkd";
            version =
              let
                cargoToml = builtins.fromTOML (builtins.readFile ./swhkd/Cargo.toml);
              in cargoToml.package.version;

            src = ./.;

            cargoLock = {
              lockFile = ./Cargo.lock;
              outputHashes = {
                "sweet-0.4.0" = "sha256-Ky2afQ5HyO1a6YT8Jjl6az1jczq+MBKeuRmFwmcvg6U=";
              };
            };

            nativeBuildInputs = with pkgs; [
              pkg-config
              scdoc
            ];

            buildInputs = with pkgs; [
              udev
            ];

            # Build specific workspace members
            buildAndTestSubdir = null;  # We're building from workspace root

            # Override the build phase to build specific binaries
            buildPhase = ''
              runHook preBuild
              cargo build --release --bin swhkd  --features no_rfkill
              cargo build --release --bin swhkd ${pkgs.lib.optionalString (!withRfkill) "--features no_rfkill"}
              cargo build --release --bin swhks
              runHook postBuild
            '';

            # Don't run tests during build
            # doCheck = false;

            postBuild = ''
              # Generate man pages from .scd files
              for f in docs/*.scd; do
                if [ -f "$f" ]; then
                  target="''${f%.scd}"
                  scdoc < "$f" | gzip > "$target.gz"
                fi
              done
            '';

            installPhase = ''
              runHook preInstall

              # Install binaries
              install -Dm755 target/release/swhkd $out/bin/swhkd
              install -Dm755 target/release/swhks $out/bin/swhks

              # Install man pages
              find ./docs -type f -name "*.1.gz" \
                -exec install -Dm644 {} -t $out/share/man/man1 \;
              find ./docs -type f -name "*.5.gz" \
                -exec install -Dm644 {} -t $out/share/man/man5 \;

              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Simple Wayland HotKey Daemon";
              homepage = "https://github.com/waycrate/swhkd";
              license = licenses.bsd2;
              platforms = platforms.linux;
              mainProgram = "swhkd";
            };
          };
        in {
          swhkd = mkSwhkd { withRfkill = true; };
          swhkd-no-rfkill = mkSwhkd { withRfkill = false; };
          default = self.packages.${system}.swhkd;

        });

      devShells = nixpkgs.lib.genAttrs targetSystems (system:
        let pkgs = pkgsFor system;
        in {
          default = pkgs.mkShell {
            name = "Swhkd-devel";
            nativeBuildInputs = with pkgs; [
              # Compilers
              cargo
              rustc
              scdoc

              # libs
              udev

              # Tools
              pkg-config
              clippy
              gdb
              gnumake
              rust-analyzer
              rustfmt
              strace
              valgrind
              zip
            ];
          };
        });
    };
}
