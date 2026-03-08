{ pkgs, config, lib, ... }:

let
  cfg = config.materializer;
  currentProjectName =
    if cfg.projectName != null
    then cfg.projectName
    else builtins.baseNameOf (toString config.devenv.root);
  currentProjectOwnFragments = lib.attrByPath [ currentProjectName ] [] cfg.ownFragments;
  effectiveMergedFragments = lib.reverseList (lib.unique (lib.reverseList (cfg.mergedFragments ++ currentProjectOwnFragments)));

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
  options = {
    materializer = {
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
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (config.instructions.fragments != []) {
      materializer.mergedFragments = lib.mkBefore config.instructions.fragments;
    })
    (lib.mkIf (effectiveMergedFragments != []) {
      files."${cfg.materializePath}".text = materializedText;
      outputs.materialized_text = pkgs.writeText "materialized-text.md" mergedMaterializerText;
    })
  ];
}
