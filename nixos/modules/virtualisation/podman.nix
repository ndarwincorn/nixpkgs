{ config, lib, pkgs, ... }:
let
  cfg = config.virtualisation.podman;

  inherit (lib) mkOption types;

  podmanPackage = (pkgs.podman.override { inherit (cfg) extraPackages; });

  # Provides a fake "docker" binary mapping to podman
  dockerCompat = pkgs.runCommandNoCC "${podmanPackage.pname}-docker-compat-${podmanPackage.version}" {
    outputs = [ "out" "bin" "man" ];
    inherit (podmanPackage) meta;
  } ''
    mkdir $out

    mkdir -p $bin/bin
    ln -s ${podmanPackage.bin}/bin/podman $bin/bin/docker

    mkdir -p $man/share/man/man1
    for f in ${podmanPackage.man}/share/man/man1/*; do
      basename=$(basename $f | sed s/podman/docker/g)
      ln -s $f $man/share/man/man1/$basename
    done
  '';

  # Copy configuration files to avoid having the entire sources in the system closure
  copyFile = filePath: pkgs.runCommandNoCC (builtins.unsafeDiscardStringContext (builtins.baseNameOf filePath)) {} ''
    cp ${filePath} $out
  '';

in
{
  meta = {
    maintainers = lib.teams.podman.members;
  };

  options.virtualisation.podman = {

    enable =
      mkOption {
        type = types.bool;
        default = false;
        description = ''
          This option enables Podman, a daemonless container engine for
          developing, managing, and running OCI Containers on your Linux System.

          It is a drop-in replacement for the <command>docker</command> command.
        '';
      };

    dockerCompat = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Create an alias mapping <command>docker</command> to <command>podman</command>.
      '';
    };

    extraPackages = mkOption {
      type = with types; listOf package;
      default = [ ];
      example = lib.literalExample ''
        [
          pkgs.gvisor
        ]
      '';
      description = ''
        Extra packages to be installed in the Podman wrapper.
      '';
    };

    libpod = mkOption {
      default = {};
      description = "Libpod configuration";
      type = types.submodule {
        options = {

          extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = ''
              Extra configuration that should be put in the libpod.conf
              configuration file
            '';

          };
        };
      };
    };

  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [ podmanPackage ]
      ++ lib.optional cfg.dockerCompat dockerCompat;

    environment.etc."containers/libpod.conf".text = ''
      cni_plugin_dir = ["${pkgs.cni-plugins}/bin/"]

    '' + cfg.libpod.extraConfig;

    environment.etc."cni/net.d/87-podman-bridge.conflist".source = copyFile "${pkgs.podman-unwrapped.src}/cni/87-podman-bridge.conflist";

    # Enable common /etc/containers configuration
    virtualisation.containers.enable = true;

  };

}
