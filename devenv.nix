{ pkgs, config, lib, ... }:

let
  cfg = config.materializer;
  pythonWithYaml = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
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
      reposRoot = cfg.localInputOverrides.reposRoot;
      urlScheme = cfg.localInputOverrides.urlScheme;
    } ''
      python3 - "$sourceYamlPath" "$matchPattern" "$reposRoot" "$urlScheme" > "$out" <<'PY'
import os
import sys
import yaml

source_yaml_path, pattern, repos_root, url_scheme = sys.argv[1:5]

with open(source_yaml_path, "r", encoding="utf-8") as handle:
    parsed = yaml.safe_load(handle) or {}

if not isinstance(parsed, dict):
    raise SystemExit("expected a top-level mapping")

inputs_block = parsed.get("inputs", {})
if inputs_block is None:
    inputs_block = {}
if not isinstance(inputs_block, dict):
    raise SystemExit("expected `inputs` to be a mapping")

def repo_name_from_url(url):
    cleaned = url.split("?", 1)[0].split("#", 1)[0]

    if cleaned.startswith("git+"):
        cleaned = cleaned[len("git+"):]

    if cleaned.startswith("github:"):
        cleaned = cleaned[len("github:"):]
    elif "github.com/" in cleaned:
        cleaned = cleaned.split("github.com/", 1)[1]

    cleaned = cleaned.rstrip("/")
    if cleaned.endswith(".git"):
        cleaned = cleaned[:-4]

    if "/" in cleaned:
        cleaned = cleaned.rsplit("/", 1)[1]

    return cleaned or None

overrides = {}

for input_name, input_spec in inputs_block.items():
    input_url = None
    copied_spec = None

    if isinstance(input_spec, dict):
        candidate_url = input_spec.get("url")
        if isinstance(candidate_url, str) and candidate_url:
            input_url = candidate_url
            copied_spec = dict(input_spec)
    elif isinstance(input_spec, str) and input_spec:
        input_url = input_spec
        copied_spec = {}

    if input_url is None or pattern not in input_url:
        continue

    repo_name = repo_name_from_url(input_url)
    if not repo_name:
        continue

    local_repo_path = os.path.join(repos_root, repo_name)
    if url_scheme == "git+file":
        local_url = f"git+file:{local_repo_path}"
    else:
        local_url = f"path:{local_repo_path}"

    copied_spec["url"] = local_url
    overrides[str(input_name)] = copied_spec

output_data = {"inputs": {}}
if not overrides:
    raise SystemExit(0)

for input_name in sorted(overrides):
    output_data["inputs"][input_name] = overrides[input_name]

yaml.safe_dump(output_data, sys.stdout, sort_keys=True, default_flow_style=False)
PY
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
        type = lib.types.str;
        default = "/home/albert/devenv/repos";
        description = "Base directory containing local repos used for generated overrides.";
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
    {
      files."${cfg.materializePath}".text = materializedText;
      outputs.materialized_text = pkgs.writeText "materialized-text.md" mergedMaterializerText;
    }
    (lib.mkIf (localInputOverridesText != "") {
      files."${cfg.localInputOverrides.outputPath}".text = localInputOverridesText;
      outputs.materialized_local_input_overrides = pkgs.writeText "devenv-local-input-overrides.yaml" localInputOverridesText;
    })
  ];
}
