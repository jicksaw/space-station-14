# Example command: nix --relaxed-sandbox build .?submodules=1#client
# --relaxed-sandbox requires current user to be in nix.settings.trusted-users

{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nix-filter.url = "github:numtide/nix-filter";

  inputs.gitignore = {
    url = "github:hercules-ci/gitignore.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, nix-filter, gitignore }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        runtime-deps = with pkgs; [
          freetype
          glfw
          libGL
          openal
          # fluidsynth needs hacking
        ];

        dotnet-sdk = pkgs.dotnetCorePackages.sdk_7_0;
        dotnet-runtime = pkgs.dotnetCorePackages.aspnetcore_7_0;

        # Hack taken from https://zimbatm.com/notes/nix-packaging-the-heretic-way
        # Could be replaced with mdarocha/nuget-packageslock2nix if project gets a NuGet lockfile
        all-nuget-deps = pkgs.stdenv.mkDerivation {
          name = "nuget-deps";

          # Requires running with --relaxed-sandbox
          # Requires current user to be in nix.settings.trusted-users
          __noChroot = true;

          # nix won't copy submodules over, or fetch them without submodules=1 flag
          # src = nix-filter.lib {
          #   root = ./.;
          #   include = with nix-filter.lib; [
          #     (isDirectory)
          #     (matchExt "csproj")
          #     (matchExt "slnf")
          #     (matchExt "sln")
          #   ];
          # };
          src = ./.;

          nativeBuildInputs = [
            pkgs.cacert
            dotnet-sdk
          ];

          # Avoid telemetry
          configurePhase = ''
            export DOTNET_NOLOGO=1
            export DOTNET_CLI_TELEMETRY_OPTOUT=1
          '';

          projectFile = "SpaceStation14.sln";

          # Pull all the dependencies for the project
          buildPhase = ''
            for project in $projectFile; do
              dotnet restore "$project" \
                -p:ContinuousIntegrationBuild=true \
                -p:Deterministic=true \
                --packages "$out"
            done
          '';

          installPhase = ":";
        };
      in
      {
        packages.client = pkgs.buildDotnetModule {
          name = "space-station-14";

          #src = gitignore.lib.gitignoreSource ./.;
          src = ./.;

          dotnet-sdk = dotnet-sdk;
          dotnet-runtime = dotnet-runtime;

          runtimeDeps = with pkgs; [
            freetype
          ];

          nativeBuildInputs = [ pkgs.python3 ];

          nugetDeps = all-nuget-deps;
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            dotnetCorePackages.sdk_7_0
            python3
            git
            omnisharp-roslyn
            netcoredbg
          ];

          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath runtime-deps;

          # OmniSharp complains about needing to install .NET 6 (or greater) when it already has .NET 6 available
          DOTNET_ROOT = pkgs.dotnetCorePackages.sdk_7_0;
        };
      }
    );
}
