# Materializer

`devenv` module for materializing files and combining instruction text across repos.

## Options (`materializer.*` namespace)

- `projectName` (default `null`: basename of `config.devenv.root`)
- `ownFragments`
- `mergedFragments`
- `materializePath` (default `AGENTS.override.md`)
- `materializeTemplate` (`plainText` or `codexConfigToml`)
- `localInputOverrides.matchPattern` (default `Alb-O`)
- `localInputOverrides.reposRoot` (default `null`: parent of `config.devenv.root`)
- `localInputOverrides.sourcePath` (default `devenv.yaml`)
- `localInputOverrides.outputPath` (default `devenv.local.yaml`)
- `localInputOverrides.urlScheme` (`path` or `git+file`, default `path`)

`localInputOverrides.*` comes from `env-local-overrides`.

## Shared Instructions (`instructions.*` namespace)

- `instructions.fragments` (list of strings, default `[]`)

`materializer` prepends `instructions.fragments` into
`materializer.mergedFragments` with `mkBefore`, so producer modules can add
shared instruction text without writing to `materializer.*` directly.

## Output

- `outputs.materialized_text` (only when the effective merged fragment list is non-empty)
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
- Ordering strategy:
  - start with `materializer.mergedFragments` in declared order
  - append `materializer.ownFragments.<current-project>` where current project is `materializer.projectName` or the basename of `config.devenv.root`
  - de-duplicate by fragment text with keep-last semantics (so the current project fragment ends up last/highest priority)
- The main materialized instruction file is only created when this effective merged fragment list is non-empty.
- For machine-local path overrides, set `materializer.localInputOverrides.reposRoot` in `devenv.local.nix` (untracked).
- Use `materializer.localInputOverrides.urlScheme = "git+file"` if you explicitly want git-backed local input URLs.
