# build-publisher

Reusable GitHub Actions workflows shared by all of my projects. A project
keeps only a thin caller workflow that `uses:` the building blocks here, so CI
logic is maintained in one place.

This repo has no pipeline of its own beyond [`validate.yml`](.github/workflows/validate.yml),
which runs [actionlint](https://github.com/rhysd/actionlint) on everything here.

## Usage

Reference a workflow by path and pin the major version tag:

```yaml
jobs:
  lint-test:
    uses: bhatnagar-afk-dev/build-publisher/.github/workflows/go-ci.yml@v1
    with:
      test-command: go test ./...
```

Each workflow does one thing; wire them together in the caller with `needs:`
and `if:`. [`examples/go-wails-app`](examples/go-wails-app) is a complete
caller (used by kuberoot): change detection → lint/test + integration → 3-OS
build → GitHub Release on `v*` tags.

Make a single gate job (`CI OK` in the example) the only required status
check in branch protection. Calling a reusable workflow prefixes its check
names (`lint-test / Lint & test`), and a skipped call reports only the caller
job's name, so requiring the individual jobs leaves PRs stuck on checks that
never report.

Permissions come from the caller. Grant the least that each job needs, e.g.
`contents: write` only on the job that calls `release-github.yml`.

## Workflows

Names follow `<verb>-<target>.yml`, so different kinds of build or publish
(e.g. `build-docker-image.yml`, `publish-npm-package.yml`) can live side by side.

| Workflow | Purpose | Key inputs | Outputs |
| --- | --- | --- | --- |
| [`detect-changes.yml`](.github/workflows/detect-changes.yml) | Tells whether a push/PR changed anything outside `ignore-patterns`. Always `true` on tags or when there is no base commit. | `ignore-patterns` | `code` |
| [`go-ci.yml`](.github/workflows/go-ci.yml) | setup → `pre-commands` → golangci-lint → `test-command` → `post-commands` | `pre-commands`, `golangci-lint-version` (empty skips), `test-command`, `post-commands`, `runs-on` | |
| [`kind-integration.yml`](.github/workflows/kind-integration.yml) | Runs `test-command` against a kind cluster (context `kind-<cluster-name>`). | `cluster-name`, `test-command` | |
| [`build-native-app.yml`](.github/workflows/build-native-app.yml) | Builds a native/desktop app on a runner matrix and uploads `<artifact-name>-<runner.os>-<arch>`. With `release: true`, also runs `package-command` and collects release assets (see below). | `runners` (JSON), `runner-overrides` (JSON), `build-command`, `artifact-path`, `artifact-name`, `release`, `package-command`, `package-files`, `release-archive`, `version`, `versioned-asset-names`, `retention-days` | |
| [`release-github.yml`](.github/workflows/release-github.yml) | Publishes the release assets from `build-native-app.yml` plus `checksums.txt` to a GitHub Release. Tags containing `-` become prereleases; re-runs replace assets. Needs `contents: write`. | `artifact-name`, `tag`, `draft` | |
| [`pr-title.yml`](.github/workflows/pr-title.yml) | Enforces Conventional Commits PR titles. Call from `pull_request_target`. | `types`, `require-scope` | |

Every workflow that runs project code also accepts the setup inputs below.

### Release assets (`build-native-app.yml`)

Release mode (`release: true`; `archive: true` is a deprecated alias) adds
these steps to every runner after the CI artifact is uploaded:

1. **Package:** runs `package-command`, e.g. to build installers. The
   `RELEASE_VERSION` env var holds the version (`version`, default: the tag).
2. **Collect:** gathers a zip/tar.gz of `artifact-path` (`release-archive`,
   default on) plus every file matching `package-files`. Each one is renamed
   to `<artifact-name>[-<version>]-<os>-<arch>.<ext>`, e.g.
   `kuberoot-macos-universal.dmg`. Two files mapping to the same name fail
   the job.
3. **Upload:** as `<artifact-name>-release-<os>-<arch>`, which
   `release-github.yml` publishes.

With `versioned-asset-names: false` the names carry no version, so
`https://github.com/<owner>/<repo>/releases/latest/download/<asset>` always
points at the newest release.

`runner-overrides` entries can set `arch`, `build-command`, `package-command`
and `package-files` for a single runner. Gate `release` on tags (and,
optionally, on `workflow_dispatch` for a packaging dry run that uploads the
assets as artifacts without publishing):

```yaml
release: ${{ github.ref_type == 'tag' || github.event_name == 'workflow_dispatch' }}
```

### Shared setup inputs

All of these go through the [`actions/setup`](actions/setup/action.yml) composite action:

| Input | Default | Notes |
| --- | --- | --- |
| `go-version-file` | `go.mod` | Empty skips Go. |
| `node-version` | `""` | Empty skips Node. |
| `node-cache-dependency-path` | `""` | Lockfile; enables the npm cache. |
| `apt-packages` | `""` | Space-separated; Linux runners only. |
| `go-tools` | `""` | Newline-separated `module@version` for `go install`. |
| `setup-commands` | `""` | Any extra shell commands. |

## Actions

- [`actions/setup`](actions/setup/action.yml): the toolchain setup shown above.
- [`actions/release-assets`](actions/release-assets/action.yml): collects a runner's release assets (archive and/or installer files) under the naming scheme above.
- [`actions/archive`](actions/archive/action.yml): **deprecated**, use `actions/release-assets`. Packages a file or directory as `<name>-<version>-<os>-<arch>`, zip on Windows/macOS and tar.gz on Linux.

## Versioning

Callers pin `@v1`. The workflows here reference this repo's own actions at
`@v1` too, because a reusable workflow cannot resolve its own ref. To release:

1. Merge to `main`.
2. Tag the exact version: `git tag v1.2.3 && git push origin v1.2.3`.
3. Move the major tag: `git tag -f v1 v1.2.3 && git push -f origin v1`.

Breaking input/output changes go to a new major (`v2`), and the internal
`@v1` action references are bumped with it.
