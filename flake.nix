{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    hercules-ci-effects.url = "github:hercules-ci/hercules-ci-effects";
  };
  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        flake-parts.flakeModules.easyOverlay
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      flake = {
        herculesCI.ciSystems = [ "x86_64-linux" ];
        effects = let
          pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
          hci-effects = inputs.hercules-ci-effects.lib.withPkgs pkgs;
        in { branch, rev, ... }: {
          macos-repeatability-test = let
            closure = pkgs.closureInfo {
              rootPaths = [ inputs.self.packages.x86_64-linux.macos-ventura-image ];
            };
          in hci-effects.mkEffect {
            secretsMap."ipfsBasicAuth" = "ipfsBasicAuth";
            buildInputs = with pkgs; [ libwebp gnutar curl nix jq ];
            effectScript = ''
              readSecretString ipfsBasicAuth .basicauth > .basicauth

              export NIX_CONFIG="experimental-features = nix-command flakes"
#              export TMPDIR="$TMP"

    export HOME=$TMP
    export ROOT=$TMP
    export NIX_STATE_DIR=$ROOT/var/nix
    export NIX_LOCALSTATE_DIR=$ROOT/var
    export NIX_LOG_DIR=$ROOT/var/log/nix
    export NIX_STATE_DIR=$ROOT/var/nix
    export NIX_CONF_DIR=$ROOT/etc
    export NIX_REMOTE="local"
    export NIX_STORE="./foo"

#              mkdir $TMPDIR nixtheplanet-test-logs
              nix-store --load-db < ${closure}/registration

              max_iterations=1
              iteration=0

              function upload_failure {
                set +e
                nix log github:matthewcroughan/nixtheplanet#macos-ventura-image > nixtheplanet-test-logs/log-$(date +%s)-$RANDOM.txt
                for i in $TMPDIR/nix-build-mac_hdd_ng.qcow2.drv-*/tmp*/*.png
                do
                  ( cwebp -q 10 $i -o $i.webp; rm $i ) &
                done
                wait
                tar --zstd -cf nixtheplanet-macos-debug.tar.zst $TMPDIR/nix-build-mac_hdd_ng.qcow2.drv-*/tmp*
                set -x
                export RESPONSE=$(curl -H @.basicauth -F file=@nixtheplanet-macos-debug.tar.zst https://ipfs-api.croughan.sh/api/v0/add)
                export CID=$(echo "$RESPONSE" | jq -r .Hash)
                set +x
                export ADDRESS="https://ipfs.croughan.sh/ipfs/$CID"

                echo NixThePlanet: Failure screen capture is available at: "$ADDRESS"
                exit 254
              }

              while [ $iteration -lt $max_iterations ]
              do
                set +e
                echo 'Running Nix'
                if ! nix build --option build-users-group "" --store ./foo --timeout 5000 github:matthewcroughan/nixtheplanet#macos-ventura-image --keep-failed -L
                then
                  upload_failure
                  echo NixThePlanet: iteration "$iteration" failed
                  exit 1
                fi
                echo 'Running Nix'
                if ! nix build --option build-users-group "" --store ./foo --timeout 5000 github:matthewcroughan/nixtheplanet#macos-ventura-image --rebuild --keep-failed -L
                then
                  upload_failure
                  echo NixThePlanet: iteration "$iteration" failed
                  exit 1
                fi
                set -e
                echo NixThePlanet: iteration "$iteration" succeeded
                ((iteration++))
              done
            '';
          };
        };
        packages.aarch64-linux.macos-ventura-image = throw "QEMU TCG doesn't emulate certain CPU features needed for MacOS x86 to boot, unsupported";
        nixosModules = {
          macos-ventura = { ... }: {
            imports = [ ./makeDarwinImage/module.nix ];
            nixpkgs.overlays = [ inputs.self.overlays.default ];
          };
        };
      };
      perSystem = { config, pkgs, system, ... }:
        let
          genOverridenDrvList = drv: howMany: builtins.genList (x: drv.overrideAttrs { name = drv.name + "-" + toString x; }) howMany;
          genOverridenDrvLinkFarm = drv: howMany: pkgs.linkFarm (drv.name + "-linkfarm-${toString howMany}") (builtins.genList (x: rec { name = toString x + "-" + drv.name; path = drv.overrideAttrs { inherit name; }; }) howMany);
        in
      {
        _module.args.pkgs = import inputs.nixpkgs {
          overlays = [
            inputs.self.overlays.default
            (self: super: {
              dosbox-x = super.dosbox-x.overrideAttrs {
                src = super.fetchFromGitHub {
                  owner = "joncampbell123";
                  repo = "dosbox-x";
                  rev = "f8e923696c29760aae974e9444229ed210d97cb9";
                  hash = "sha256-3VP0dTAntWPzrGOIxI22/Y6ienq9rYUf7wMlHd6flu4=";
                };
              };
            })
          ];
          inherit system;
        };
        overlayAttrs = config.legacyPackages;
        legacyPackages = {
          makeDarwinImage = pkgs.callPackage ./makeDarwinImage {
            # substitute relative input with absolute input
            qemu_kvm = pkgs.qemu_kvm.overrideAttrs {
              prePatch = ''
                substituteInPlace ui/ui-hmp-cmds.c --replace "qemu_input_queue_rel(NULL, INPUT_AXIS_X, dx);" "qemu_input_queue_abs(NULL, INPUT_AXIS_X, dx, 0, 1920);"
                substituteInPlace ui/ui-hmp-cmds.c --replace "qemu_input_queue_rel(NULL, INPUT_AXIS_Y, dy);" "qemu_input_queue_abs(NULL, INPUT_AXIS_Y, dy, 0, 1080);"
              '';
            };
          };
          makeMsDos622Image = pkgs.callPackage ./makeMsDos622Image {};
          makeWin30Image = pkgs.callPackage ./makeWin30Image {};
          makeWfwg311Image = pkgs.callPackage ./makeWfwg311Image {};
          makeSystem7Image = pkgs.callPackage ./makeSystem7Image {};
        };
        apps = {
          macos-ventura = {
            type = "app";
            program = config.packages.macos-ventura-image.runScript;
          };
          msdos622 = {
            type = "app";
            program = config.packages.msdos622-image.runScript;
          };
          win30 = {
            type = "app";
            program = config.packages.win30-image.runScript;
          };
          wfwg311 = {
            type = "app";
            program = config.packages.wfwg311-image.runScript;
          };
        };
        packages = rec {
          macos-ventura-image = config.legacyPackages.makeDarwinImage {};
          msdos622-image = config.legacyPackages.makeMsDos622Image {};
          win30-image = config.legacyPackages.makeWin30Image {};
          wfwg311-image = config.legacyPackages.makeWfwg311Image {};
          #system7-image = config.legacyPackages.makeSystem7Image {};
          #macos-repeatability-test = genOverridenDrvLinkFarm (macos-ventura-image.overrideAttrs { repeatabilityTest = true; }) 3;
          #wfwg311-repeatability-test = genOverridenDrvLinkFarm wfwg311-image 1000;
          #win30-repeatability-test = genOverridenDrvLinkFarm win30-image 1000;
          #msDos622-repeatability-test = genOverridenDrvLinkFarm msdos622-image 1000;
        };
        checks = {
          macos-ventura = pkgs.callPackage ./makeDarwinImage/vm-test.nix { nixosModule = inputs.self.nixosModules.macos-ventura; };
        };
      };
    };
}
