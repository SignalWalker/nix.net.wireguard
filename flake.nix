{
  description = "NixOS module for easier setup of wireguard networks and tunnels.";
  inputs = {};
  outputs = inputs @ {self, ...}: {
    nixosModules.default = import ./nixos-module.nix;
  };
}
