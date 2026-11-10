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

- builds all three flavors on native AMD64 (`ubuntu-latest`) and ARM64
  (`ubuntu-24.04-arm`) runners, with BuildKit provenance and SBOM attestations;
- pushes run-scoped `<flavor>-candidate-<run-id>-<attempt>-<arch>` indexes;
- pulls each platform by immutable digest, scans `full`, and runs the existing
  `--no-build all` smoke suite, including authentication, all kernels, and lifecycle;
- records digests only after validation succeeds, then combines the validated
  indexes into `<flavor>-candidate-<run-id>-<attempt>` and promotes that index.

Compilation and runtime validation use no QEMU. Evcxr uses its checksum-verified
upstream Linux AMD64 binary; upstream does not publish Linux ARM64 binaries, so
ARM64 compiles the locked source natively. The Rust installation layer precedes
Jupyter packages so Python-only updates do not recompile it.

Each architecture imports and exports its own registry cache, avoiding concurrent
writers replacing one another's cache. CI imports the AMD64 release cache.
Registry cache-export failures are reported but do not fail the build; image
exports and all validation/promotion steps remain mandatory. Invalid cache-export
configuration can still fail the build.
A new cache starts cold; subsequent releases reuse completed layers. BuildKit
cache mounts retain downloads only on the same builder and are not exported with
registry layer caches. Validation never rebuilds the toolchain layers.

With both architecture jobs running concurrently, the critical path is
preparation + the slower native build/scan/smoke job + publication. The job
limits total 10 + 160 + 10 = 180 minutes on that path; this is not a workflow
wall-clock deadline. Runner queues, serialized scheduling, and reruns add time.

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
The queue does not sort by SemVer. Rerunning native build jobs creates fresh
candidates; retrying only publication reuses the recorded, validated digests.
If their artifacts have expired, rerun the build jobs. Rerunning an older stable
tag can move shared aliases backward; rebuilding it can also replace exact
version tags if upstream build inputs have changed.

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
the `code` flavor. Patch publishing still builds ARM64 through QEMU and can incur
a slow cold Evcxr build.

## Candidate retention

Candidate tags accumulate after both successful and failed runs. Assembled
multi-architecture candidates share a GHCR package version with release tags;
deleting that version also removes the released artifact. Retain these versions.

For conservative manual cleanup, review candidate-only root index versions
from completed runs older than 30 days and delete only versions whose non-empty
tag list contains only candidate tags. Preserve every version with another tag,
and never bulk-delete untagged versions: retained indexes reference untagged platform
and attestation manifests. The workflow performs no registry deletion.

## Notes

- Workflows use `GITHUB_TOKEN` with `packages: read` for smoke cache imports and
  `packages: write` for publishing; no personal access token should be needed.
- Build cache is published separately from release images:
  `ghcr.io/jo-cube/workspace-cache-amd64` and `workspace-cache-arm64`.
  Patch-branch publishing continues to use `workspace-cache`.
- Keep `workspace` public if the images should be anonymously pullable. The
  cache packages can stay private if only GitHub Actions needs read/write access.
- If a publish job fails with a permissions error, check the repository's
  Actions workflow permissions and package permissions in GitHub settings.
- After the first successful publish, check the GHCR package visibility. GitHub
  may create the package as private; switch it to public if these images should
  be publicly pullable.
- The workflows use `docker buildx bake`; do not replace them with
  `docker compose up --build`.
