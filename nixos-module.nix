{
  config,
  pkgs,
  lib,
  ...
}:
with builtins; let
  std = pkgs.lib;
  wg = config.networking.wireguard;
  wgPeer = lib.types.submoduleWith {
    modules = [
      ({
        config,
        lib,
        pkgs,
        ...
      }: {
        options = with lib; {
          publicKey = mkOption {
            type = types.str;
          };
          presharedKeyFile = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          allowedIps = mkOption {
            type = types.listOf types.str;
            default = [];
          };
          endpoint = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          persistentKeepAlive = mkOption {
            type = types.int;
            default = 0;
          };
          routeTable = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          routeMetric = mkOption {
            type = types.nullOr types.int;
            default = null;
          };
        };
        config = {};
      })
    ];
  };
in {
  options = with lib; {
    networking.wireguard = {
      networks = mkOption {
        type = types.attrsOf (types.submoduleWith {
          modules = [
            ({
              config,
              lib,
              pkgs,
              name,
              ...
            }: {
              options = with lib; {
                enable = mkEnableOption "wireguard network :: ${name}";
                privateKeyFile = mkOption {
                  type = types.str;
                  description = "runtime path of private key file";
                };
                peers = mkOption {
                  type = types.listOf wgPeer;
                  description = "Wireguard peer configurations.";
                  default = [];
                };
                # netdev config
                netdev = {
                  port = mkOption {
                    type = types.either types.port (types.enum ["auto"]);
                    description = "The UDP port on which to listen, or `\"auto\"` to automatically select a free port.";
                    example = 51860;
                    default = "auto";
                  };
                  openFirewall = (mkEnableOption "open the listen port on the firewall") // { default = config.port != "auto"; };
                  firewallMark = mkOption {
                    type = types.nullOr types.int;
                    default = null;
                  };
                  routeTable = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                  };
                  routeMetric = mkOption {
                    type = types.nullOr types.int;
                    default = null;
                  };
                  extraConfig = mkOption {
                    type = types.attrsOf types.anything;
                    default = {};
                  };
                };
                # network config
                network = {
                  addresses = mkOption {
                    type = types.listOf types.str;
                    description = "Addresses held by this node.";
                    default = [];
                  };
                  # TODO :: make this address-specific
                  addPrefixRoute = mkOption {
                    type = types.bool;
                    default = true;
                  };
                  dns = mkOption {
                    type = types.listOf types.str;
                    default = [];
                  };
                  domains = mkOption {
                    type = types.listOf types.str;
                    default = [];
                  };
                  extraConfig = mkOption {
                    type = types.attrsOf types.anything;
                    default = {};
                  };
                };
              };
              config = {};
            })
          ];
        });
        default = {};
      };
    };
  };
  imports = [./nixos-module/tunnel.nix];
  config = lib.mkIf (any (net: net.enable) (attrValues wg.networks)) {
    systemd.network.netdevs =
      std.mapAttrs (netname: network: (lib.mkMerge [
        {
          enable = network.enable;
          netdevConfig = {
            Name = netname;
            Kind = "wireguard";
          };
          wireguardConfig = lib.mkMerge [
            {
              ListenPort = network.netdev.port;
              PrivateKeyFile = network.privateKeyFile;
            }
            (lib.mkIf (network.netdev.routeTable != null) {
              RouteTable = network.netdev.routeTable;
            })
            (lib.mkIf (network.netdev.firewallMark != null) {
              FirewallMark = network.netdev.firewallMark;
            })
            (lib.mkIf (network.netdev.routeMetric != null) {
              RouteMetric = network.netdev.routeMetric;
            })
          ];
          wireguardPeers = map (peer:
            lib.mkMerge [
              {
                PublicKey = peer.publicKey;
                AllowedIPs = peer.allowedIps;
                PersistentKeepalive = peer.persistentKeepAlive;
              }
              (lib.mkIf (peer.presharedKeyFile != null) {
                PresharedKeyFile = peer.presharedKeyFile;
              })
              (lib.mkIf (peer.endpoint != null) {
                Endpoint = peer.endpoint;
              })
              (lib.mkIf (peer.routeTable != null) {
                RouteTable = peer.routeTable;
              })
              (lib.mkIf (peer.routeMetric != null) {
                RouteMetric = peer.routeMetric;
              })
            ])
          network.peers;
        }
        network.netdev.extraConfig
      ]))
      wg.networks;

    systemd.network.networks =
      std.mapAttrs (netname: network: (lib.mkMerge [
        {
          enable = network.enable;
          matchConfig = {
            Name = netname;
            Type = "wireguard";
          };
          linkConfig = {
            RequiredForOnline = "no";
          };
          networkConfig = {
            # DHCP = false;
            # LLMNR = false;
          };
          dns = network.network.dns;
          addresses =
            map (addr: {
              Address = addr;
              AddPrefixRoute =
                if network.network.addPrefixRoute
                then "yes"
                else "no";
              # Scope = "link";
            })
            network.network.addresses;
        }
        (lib.mkIf (network.network.domains != []) {
          domains = network.network.domains;
        })
        network.network.extraConfig
      ]))
      wg.networks;

    networking.firewall.allowedUDPPorts =
      foldl' (
        acc: netName: let
          net = wg.networks.${netName};
        in
          # TODO :: warn if openFirewall && net.port == "auto"
          if net.enable && net.netdev.port != "auto" && net.netdev.openFirewall
          then acc ++ [net.netdev.port]
          else acc
      )
      [] (attrNames wg.networks);
  };
}
