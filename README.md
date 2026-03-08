# Materializer

`devenv` module for merging agents instruction fragments across repos.

## Options

- `materializer.ownFragments`
- `materializer.mergedFragments`
- `materializer.materializePath` (default `AGENTS.override.md`)
- `materializer.materializeTemplate` (`plainText` or `codexConfigToml`)
- `materializer.localInputOverrides.matchPattern` (default `Alb-O`)
- `materializer.localInputOverrides.reposRoot` (default `/home/albert/devenv/repos`)
- `materializer.localInputOverrides.sourcePath` (default `devenv.yaml`)
- `materializer.localInputOverrides.outputPath` (default `devenv.local.yaml`)
- `materializer.localInputOverrides.urlScheme` (`path` or `git+file`, default `path`)

## Output

- `outputs.materialized_text`
- `outputs.materialized_local_input_overrides` (only when at least one input URL matches `materializer.localInputOverrides.matchPattern`)

Example generated override:

```yaml
inputs:
  committer:
    url: path:/home/albert/devenv/repos/committer
    flake: false
    any_other_key:
      nested: value
```

## Notes

- The `codexConfigToml` value for the `materializeTemplate` option uses codex's `developer_instructions` config key, materializing `.codex/config.toml` instead of `AGENTS.override.md`.
- `devenv.local.yaml` is materialized through `files` on shell entry as a symlink to the Nix store (same mechanism as `AGENTS.override.md`) only when at least one input matches.
- Use `materializer.localInputOverrides.urlScheme = "git+file"` if you explicitly want git-backed local input URLs.
- For matched inputs, all existing sibling/child keys are preserved; only `url` is rewritten.
