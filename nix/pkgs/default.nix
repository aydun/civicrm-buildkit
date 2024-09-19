/**
 * Provide a list of packages which we have defined or customized locally.
 *
 * TODO: Consider using callPackages convention, e.g. http://lethalman.blogspot.com/2014/09/nix-pill-13-callpackage-design-pattern.html
 */

let

  dists = (import ../pins);
  pkgs = dists.default;
  stdenv = pkgs.stdenv;
  isAppleM1 = stdenv.isDarwin && stdenv.isAarch64;

  fetchPhar = (import ../funcs).fetchPhar;
  jsonContent = builtins.fromJSON (builtins.readFile ../../phars.json);
  mapAttrs = (f: set: builtins.listToAttrs (builtins.map (attr: { name = attr; value = f attr set.${attr}; }) (builtins.attrNames set)));
  jsonToPhar = name: attrs: fetchPhar {
    name = name;
    url = attrs.url;
    sha256 = attrs.sha256;
  };
  pharDirectives = (mapAttrs jsonToPhar jsonContent);

  callPackage = path: overrides:
    let f = import path;
    in f ((builtins.intersectAttrs (builtins.functionArgs f) pkgs) // overrides);

  ## ifSupported: If the "condition" is true, then return "value". Otherwise, throw an error.
  ifSupported = name: condition: value: (if condition then value else throw "Package ${name} is unsupported in this environment");
  # ifSupported = name: condition: value: (if condition then value else null);

in pharDirectives // rec {

   mysql56 = ifSupported "mysql56" (!isAppleM1) ((import ./mysql56/default.nix).mysql56);
   mysql57 = dists.default.mysql57;
   mysql80 = (import ./mysql80/default.nix);
   mysql84 = dists.v2405.mysql84;
   mysql90 = dists.v2405.mysql90;
   mariadb105 = if isAppleM1 then null else dists.v2105.mariadb;
   mariadb106 = dists.default.mariadb;

   php71 = ifSupported "php71" (!isAppleM1) (import ./php71/default.nix);
   php72 = ifSupported "php72" (!isAppleM1) (import ./php72/default.nix);
   php73 = ifSupported "php73" (!isAppleM1) (import ./php73/default.nix);
   bknixPhpstormAdvisor = import ./bknixPhpstormAdvisor/default.nix;
   bknixProfile = import ./bknixProfile/default.nix;
   php74 = import ./php74/default.nix;
   php80 = import ./php80/default.nix;
   php81 = import ./php81/default.nix;
   php82 = import ./php82/default.nix;
   php83 = import ./php83/default.nix;
   php84 = import ./php84/default.nix;
   transifexClient = import ./transifexClient/default.nix;
   ramdisk = callPackage (fetchTarball https://github.com/totten/ramdisk/archive/v0.1.2.tar.gz) {};

   # We don't actually modify the tzdata package, but we should have a singular pinning so that it same pkg is used in different flows.
   tzdata = pkgs.tzdata;

}
