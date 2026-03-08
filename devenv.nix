{ pkgs, config, lib, ... }:

let
  cfg = config.materializer;
  pythonWithYaml = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  localInputOverridesScript = ./scripts/materialize_local_input_overrides.py;
  currentProjectName =
    if cfg.projectName != null
    then cfg.projectName
    else builtins.baseNameOf (toString config.devenv.root);
  currentProjectOwnFragments = lib.attrByPath [ currentProjectName ] [] cfg.ownFragments;
  effectiveMergedFragments = lib.reverseList (lib.unique (lib.reverseList (cfg.mergedFragments ++ currentProjectOwnFragments)));
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

  collapseConsecutiveBlankLines =
    text:
    let
      folded = lib.foldl' (
        acc: line:
        let
          isBlank = builtins.match "^[ \t\r]*$" line != null;
        in
        if isBlank && acc.previousBlank
        then acc
        else {
          previousBlank = isBlank;
          revLines = [ line ] ++ acc.revLines;
        }
      ) {
        previousBlank = false;
        revLines = [];
      } (lib.splitString "\n" text);
    in
    lib.concatStringsSep "\n" (lib.reverseList folded.revLines);
  rawMergedMaterializerText = lib.concatStringsSep "\n" effectiveMergedFragments;
  mergedMaterializerText = collapseConsecutiveBlankLines rawMergedMaterializerText;
  materializedText =
    if cfg.materializeTemplate == "codexConfigToml"
    then lib.concatStringsSep "\n" [
      "developer_instructions = '''"
      mergedMaterializerText
      "'''"
      ""
    ]
    else mergedMaterializerText;
in
{
  options.materializer = {
    projectName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Current project key used to resolve `ownFragments.<projectName>`. Defaults to the basename of `config.devenv.root`.";
    };

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
    (lib.mkIf (effectiveMergedFragments != []) {
      files."${cfg.materializePath}".text = materializedText;
      outputs.materialized_text = pkgs.writeText "materialized-text.md" mergedMaterializerText;
    })
    (lib.mkIf (localInputOverridesText != "") {
      files."${cfg.localInputOverrides.outputPath}".text = localInputOverridesText;
      outputs.materialized_local_input_overrides = pkgs.writeText "devenv-local-input-overrides.yaml" localInputOverridesText;
    })
  ];
}
