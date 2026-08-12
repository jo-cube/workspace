# Releasing

Images are published to GitHub Container Registry by GitHub Actions. The
published image name is:

```text
ghcr.io/jo-cube/workspace
```

Only these flavors are published:

- `code`
- `platform`
- `full`

## Stable releases

Push a SemVer tag from a commit that is already on `main`:

```bash
git switch main
git pull --ff-only
git tag v1.2.3
git push origin v1.2.3
```

The release workflow verifies that the tagged commit is reachable from
`origin/main` before publishing. It also:

- builds the inherited `full` image on the native runner for scanning;
- reports fixed Critical vulnerabilities with Trivy without blocking publication;
- publishes `linux/amd64` and `linux/arm64` images; and
- attaches BuildKit provenance and an SBOM to each published image.

These checks make a release a reviewed, traceable artifact. They do not claim
that builds are byte-for-byte reproducible: several upstream installers and
base package repositories still resolve content at build time.

Stable tags publish:

```text
code-1.2.3, code-1.2, code-1, code-latest
platform-1.2.3, platform-1.2, platform-1, platform-latest
full-1.2.3, full-1.2, full-1, full-latest, latest
```

## Pre-releases

Pre-release tags use normal SemVer suffixes:

```bash
git tag v1.2.3-rc.1
git push origin v1.2.3-rc.1
```

Pre-release tags publish only exact flavor tags:

```text
code-1.2.3-rc.1
platform-1.2.3-rc.1
full-1.2.3-rc.1
```

They do not update `latest`, major, minor, or `*-latest` tags.

## Patch branch images

Branches under `patch/**` publish test images for the same three flavors:

```text
code-patch-<branch>
code-patch-<branch>-<short-sha>
platform-patch-<branch>
platform-patch-<branch>-<short-sha>
full-patch-<branch>
full-patch-<branch>-<short-sha>
```

Patch images are for validation only. They do not update stable or latest tags.
They include BuildKit provenance and an SBOM, while the branch CI smoke-tests
the `code` flavor.

## Notes

- Workflows use `GITHUB_TOKEN` with `packages: read` for smoke cache imports and
  `packages: write` for publishing; no personal access token should be needed.
- Build cache is published separately from release images:
  `ghcr.io/jo-cube/workspace-cache`.
- Keep `workspace` public if the images should be anonymously pullable. The
  `workspace-cache` package can stay private if you only need GitHub Actions to
  read/write it.
- If a publish job fails with a permissions error, check the repository's
  Actions workflow permissions and package permissions in GitHub settings.
- After the first successful publish, check the GHCR package visibility. GitHub
  may create the package as private; switch it to public if these images should
  be publicly pullable.
- The workflows use `docker buildx bake`; do not replace them with
  `docker compose up --build`.
