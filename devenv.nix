{ pkgs, config, lib, ... }:

let
  cfg = config.materializer;
  pythonWithYaml = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  localInputOverridesScript = ./scripts/materialize_local_input_overrides.py;
  localInputOverridesReposRoot =
    if cfg.localInputOverrides.reposRoot != null
    then cfg.localInputOverrides.reposRoot
    else builtins.dirOf config.devenv.root;
  localInputOverridesSourcePath =
    if lib.hasPrefix "/" cfg.localInputOverrides.sourcePath
    then cfg.localInputOverrides.sourcePath
    else "${config.devenv.root}/${cfg.localInputOverrides.sourcePath}";
  localInputOverridesText =
    if builtins.pathExists localInputOverridesSourcePath
    then builtins.readFile (pkgs.runCommand "materialized-local-input-overrides.yaml" {
      nativeBuildInputs = [ pythonWithYaml ];
      passAsFile = [ "sourceYaml" ];
      sourceYaml = builtins.readFile localInputOverridesSourcePath;
      matchPattern = cfg.localInputOverrides.matchPattern;
      reposRoot = localInputOverridesReposRoot;
      urlScheme = cfg.localInputOverrides.urlScheme;
    } ''
      python3 ${localInputOverridesScript} "$sourceYamlPath" "$matchPattern" "$reposRoot" "$urlScheme" > "$out"
    '')
    else "";

  materializedText =
    if cfg.materializeTemplate == "codexConfigToml"
    then lib.concatStringsSep "\n" [
      "developer_instructions = '''"
      mergedMaterializerText
      "'''"
      ""
    ]
    else mergedMaterializerText;
  mergedMaterializerText = lib.concatStringsSep "\n" cfg.mergedFragments;
in
{
  options.materializer = {
    ownFragments = lib.mkOption {
      type = with lib.types; attrsOf (listOf str);
      default = {};
      description = "Project-owned instruction fragments keyed by project name.";
    };

    mergedFragments = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
      description = "Instruction text fragments merged from upstream to downstream repos.";
    };

    materializePath = lib.mkOption {
      type = lib.types.str;
      default = "AGENTS.override.md";
      description = "Relative or absolute output file path to materialize.";
    };

    materializeTemplate = lib.mkOption {
      type = lib.types.enum [ "plainText" "codexConfigToml" ];
      default = "plainText";
      description = "Materialization template: plain text or Codex config TOML.";
    };

    localInputOverrides = {
      matchPattern = lib.mkOption {
        type = lib.types.str;
        default = "Alb-O";
        description = "Substring used to match input URLs eligible for local git+file overrides.";
      };

      reposRoot = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Base directory containing local repos used for generated overrides. When null, materializer falls back to `builtins.dirOf config.devenv.root`.";
      };

      sourcePath = lib.mkOption {
        type = lib.types.str;
        default = "devenv.yaml";
        description = "Source devenv YAML file to scan for inputs and URLs.";
      };

      outputPath = lib.mkOption {
        type = lib.types.str;
        default = "devenv.local.yaml";
        description = "Output path for materialized local input override YAML.";
      };

      urlScheme = lib.mkOption {
        type = lib.types.enum [ "path" "git+file" ];
        default = "path";
        description = "URL scheme used for generated local repo overrides.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (mergedMaterializerText != "") {
      files."${cfg.materializePath}".text = materializedText;
      outputs.materialized_text = pkgs.writeText "materialized-text.md" mergedMaterializerText;
    })
    (lib.mkIf (localInputOverridesText != "") {
      files."${cfg.localInputOverrides.outputPath}".text = localInputOverridesText;
      outputs.materialized_local_input_overrides = pkgs.writeText "devenv-local-input-overrides.yaml" localInputOverridesText;
    })
  ];
}
