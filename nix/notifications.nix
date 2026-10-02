{
  pkgs,
  notifier ? if pkgs.stdenv.hostPlatform.isDarwin then (pkgs.alerter or null) else null,
  settings ? { },
  labels ? "agent_label() { printf '%s\n' \"$1\"; }",
}:
let
  configFile = (pkgs.formats.json { }).generate "agent-notify-config.json" (
    pkgs.lib.recursiveUpdate (import ./notification-defaults.nix) settings
  );
  schema = ../schemas/notification-config.schema.json;
  checkedConfig =
    pkgs.runCommand "agent-notify-config.json" { nativeBuildInputs = [ pkgs.check-jsonschema ]; }
      ''
        check-jsonschema --schemafile ${schema} ${configFile}
        cp ${configFile} "$out"
      '';
  fragments =
    names:
    builtins.concatStringsSep "\n" (map (name: builtins.readFile (../runtime + "/${name}")) names);
  base = fragments [
    "paths.sh"
    "agent-group.sh"
    "agent-review-suffix.sh"
    "agent-identity.sh"
    "agent-classify.sh"
  ];
  package = pkgs.writeShellApplication {
    name = "agent-notify";
    runtimeInputs = [
      pkgs.jq
      pkgs.git
      pkgs.coreutils
      pkgs.wezterm
    ]
    ++ pkgs.lib.optional (notifier != null) notifier;
    bashOptions = [ ];
    text =
      base
      + "\n"
      + labels
      + "\n"
      + ''
        notify_config=${checkedConfig}
      ''
      + builtins.readFile ../runtime/agent-notify.sh;
  };
in
package
// {
  configFile = checkedConfig;
  inherit schema;
}
