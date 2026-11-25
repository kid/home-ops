# home-manager uses the system's nixpkgs and installs into the user profile,
# on NixOS and darwin hosts alike.
_: {
  den.aspects.hm-defaults.os.home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}
