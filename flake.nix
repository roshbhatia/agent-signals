{
  description = "agent-signals";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  outputs =
    { self, nixpkgs }:
    let
      each = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    in
    {
      lib.mkNotifier = import ./nix/notifications.nix;
      packages = each (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          notifier = self.lib.mkNotifier { inherit pkgs; };
          default = pkgs.buildGoModule {
            pname = "agent-state";
            version = "0.1.0";
            src = ./.;
            vendorHash = "sha256-LLhR96vCSXd90RwwoFHEtMCik4p1iVVU2YGcIkIuR9k=";
            subPackages = [ "cmd/agent-state" ];
            nativeCheckInputs = [ pkgs.git ];
            checkPhase = "runHook preCheck; go test ./...; runHook postCheck";
            meta.mainProgram = "agent-state";
          };
        }
      );
      checks = each (system: {
        package = self.packages.${system}.default;
        notifications = import ./nix/check-notifications.nix { pkgs = nixpkgs.legacyPackages.${system}; };
        notifier = self.packages.${system}.notifier;
      });
      devShells = each (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.go
              pkgs.git
              pkgs.nixfmt
              pkgs.shellcheck
              pkgs.shfmt
              pkgs.python3
            ];
          };
        }
      );
      formatter = each (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
          name = "format";
          runtimeInputs = [ pkgs.nixfmt ];
          text = ''exec nixfmt "$@" flake.nix nix/notifications.nix'';
        }
      );
    };
}
