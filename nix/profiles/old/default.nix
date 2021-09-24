/**
 * The `min` list identifies the lowest recommended versions of the system requirements.
 *
 * We rely on a mix of packages from Nix upstream v18.03 (`pkgs`) and custom forks (`bkpkgs`).
 */
let
    pkgs = import (import ../../pins/18.03.nix) {};
    pkgs_1809 = import (import ../../pins/18.09.nix) {};
    pkgs_2105 = import (import ../../pins/21.05.nix) {};
    bkpkgs = import ../../pkgs;

in (import ../base/default.nix) ++ (import ../mgmt/default.nix) ++ [

    bkpkgs.php71
    pkgs_2105.nodejs-14_x
    pkgs_2105.apacheHttpd
    pkgs_1809.mailcatcher
    pkgs.memcached
    bkpkgs.mysql55
    pkgs.redis
    bkpkgs.transifexClient

]
