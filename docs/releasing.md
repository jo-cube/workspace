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

- builds all three flavors once for `linux/amd64` and `linux/arm64`, with
  BuildKit provenance and SBOM attestations;
- pushes run-scoped `<flavor>-candidate-<run-id>-<attempt>` tags and records their
  immutable index digests;
- pulls each platform by digest, scans `full`, and runs the existing smoke suite
  with `--no-build all`, including application authentication, kernels, and lifecycle;
- promotes those same indexes to the release tags only after both platforms pass.

AMD64 validation runs natively on `ubuntu-latest`; ARM64 builds and tests use
QEMU. Emulation checks the ARM64 binaries and userspace, but does not establish
native ARM hardware behavior or performance. The existing registry caches are
reused; validation does not rebuild the toolchain layers.

Trivy reports fixed Critical vulnerabilities without blocking promotion, as
before. Scanner errors, failed database downloads, build failures, and smoke
failures block all release-tag updates. Candidate tags may remain after a failed
run and are not validated releases. Promotion copies the complete indexes,
preserving their platform manifests and attestation references, without rebuilding.
Smoke checks exercise the two runnable platform variants; they do not verify
provenance or SBOM contents.
Registry tag updates are not transactional: a promotion error can leave some
tags updated, but every promoted artifact has passed validation.

These checks do not claim byte-for-byte reproducibility: several upstream
installers and base package repositories still resolve content at build time.

Stable tags publish:

```text
code-1.2.3, code-1.2, code-1, code-latest
platform-1.2.3, platform-1.2, platform-1, platform-latest
full-1.2.3, full-1.2, full-1, full-latest, latest
```

Release runs share one queue to prevent interleaved tag updates across versions.
The queue does not sort by SemVer. Every rerun builds and validates a fresh
candidate; rerunning an older stable tag can move shared aliases backward and
replace its exact version tags if upstream build inputs have changed.

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

## Candidate retention

Candidate tags accumulate after both successful and failed runs. Successful
candidates share a GHCR package version with release tags; deleting that
version also removes the released artifact. Retain these versions.

For conservative manual cleanup, review candidate-only root index versions
from completed runs older than 30 days and delete only versions whose non-empty
tag list contains only candidate tags. Preserve every version with another tag,
and never bulk-delete untagged versions: retained indexes reference untagged platform
and attestation manifests. The workflow performs no registry deletion.

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
