{
  pkgs,
  notifier ? pkgs.alerter or null,
  labels ? "agent_label() { printf '%s\n' \"$1\"; }",
}:
let
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
in
pkgs.writeShellApplication {
  name = "agent-notify";
  runtimeInputs = [
    pkgs.jq
    pkgs.git
    pkgs.coreutils
    pkgs.wezterm
  ]
  ++ pkgs.lib.optional (notifier != null) notifier;
  bashOptions = [ ];
  text = base + "\n" + labels + "\n" + builtins.readFile ../runtime/agent-notify.sh;
}
