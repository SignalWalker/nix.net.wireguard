{
  config,
  pkgs,
  lib,
  ...
}:
with builtins; let
  std = pkgs.lib;
  tunnels = config.networking.wireguard.tunnels;
in {
  options = with lib; {
    networking.wireguard = {
      tunnels = mkOption {
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
                enable = mkEnableOption "wireguard tunnel: ${name}";
                port = mkOption {
                  type = types.either types.port (types.enum ["auto"]);
                  example = 51860;
                  default = "auto";
                };
                privateKeyFile = mkOption {
                  type = types.str;
                  description = "runtime path of private key file";
                };
                dns = mkOption {
                  type = types.listOf types.str;
                  default = [];
                };
                addresses = mkOption {
                  type = types.listOf types.str;
                };
                peer = {
                  publicKey = mkOption {
                    type = types.str;
                  };
                  presharedKeyFile = mkOption {
                    type = types.str;
                  };
                  endpoint = mkOption {
                    type = types.str;
                  };
                  allowedIps = mkOption {
                    type = types.listOf types.str;
                  };
                };
                table = mkOption {
                  type = types.int;
                  example = 51820;
                };
                fwMark = mkOption {
                  type = types.int;
                  default = config.table;
                };
                priority = mkOption {
                  type = types.int;
                  example = 10;
                };
                mtu = mkOption {
                  type = types.nullOr types.ints.unsigned;
                  default = null;
                };
                activationPolicy = mkOption {
                  type = types.nullOr (types.enum ["always-up" "up" "manual" "down" "always-down" "bound"]);
                  default = "manual";
                };
                routingPolicyRules = mkOption {
                  type = types.listOf types.anything;
                  default = [
                    {
                      FirewallMark = config.fwMark;
                      InvertRule = true;
                      Table = config.table;
                      Priority = config.priority + 1;
                      Family = "both";
                    }
                    {
                      Table = "main";
                      Priority = config.priority;
                      SuppressPrefixLength = 0;
                      Family = "both";
                    }
                  ];
                };
              };
              config = {};
            })
          ];
        });
      };
    };
  };
  disabledModules = [];
  imports = [];
  config = lib.mkIf (any (tun: tun.enable) (attrValues tunnels)) {
    networking.wireguard.networks = std.mapAttrs (tunName: tunnel:
      lib.mkIf tunnel.enable {
        enable = tunnel.enable;
        inherit (tunnel) privateKeyFile;
        peers = [
          (tunnel.peer
            // {
              persistentKeepAlive = 15;
            })
        ];
        netdev = {
          inherit (tunnel) port;
          openFirewall = true;
          firewallMark = tunnel.fwMark;
        };
        network = {
          inherit (tunnel) dns addresses;
          addPrefixRoute = false;
          extraConfig = {
            linkConfig = lib.mkMerge [
              (lib.mkIf (tunnel.activationPolicy != null) {
                ActivationPolicy = tunnel.activationPolicy;
              })
              (lib.mkIf (tunnel.mtu != null) {
                MTUBytes = toString tunnel.mtu;
              })
            ];
            networkConfig = {
              # DNSDefaultRoute = true;
              Domains = "~.";
            };
            inherit (tunnel) routingPolicyRules;
            routes =
              map (dest: {
                Destination = dest;
                Table = tunnel.table;
                Scope = "link";
              })
              tunnel.peer.allowedIps;
          };
        };
      })
    tunnels;

    # this prevents nftables from breaking tunnels
    networking.firewall.checkReversePath = "loose";
  };
  meta = {};
}
