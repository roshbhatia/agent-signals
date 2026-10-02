{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [ ps.jsonschema ]);
  defaults = pkgs.writeText "notification-defaults.json" (
    builtins.toJSON (import ./notification-defaults.nix)
  );
in
pkgs.runCommand "notification-contracts"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.jq
      pkgs.git
      pkgs.coreutils
    ];
  }
  ''
    ${python}/bin/python3 ${../tests/notifications.py} ${../runtime} ${../schemas/notification-config.schema.json} ${defaults}
    touch "$out"
  ''
