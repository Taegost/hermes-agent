---
title: "Migrating the hermes-agent wrapper image across a major Hermes overhaul (v2026.8.3 → v0.22.5)"
date: 2026-10-31
category: workflow-issues
module: docker-image
problem_type: workflow_issue
component: tooling
severity: high
applies_when:
  - "Bumping the hermes-agent base image version in this repo"
  - "Moving from date-versioned tags (v2026.8.3) to semver tags (v0.22.5)"
  - "Restoring uv or global npm tools on PATH in v0.22.x-derived images"
  - "Adding third-party Python tools (such as honcho-ai) to a Hermes deployment"
  - "Choosing the final USER in a Dockerfile derived from hermes-agent v0.22.x"
symptoms:
  - "uv resolves nowhere on PATH in v0.22.x images (pm-pinned at /opt/hermes/tools/uv-*/uv)"
  - "npm 12 global installs land in a pm-managed prefix that is not on PATH"
  - "npm 12 blocks claude-code postinstall, which fetches the platform-native binary"
  - "Container fails s6 bootstrap when the final USER is hermes"
  - "honcho-ai no longer ships inside the sealed /opt/hermes/.venv"
root_cause: incomplete_setup
resolution_type: migration
related_components:
  - development_workflow
  - documentation
tags:
  - docker
  - hermes-agent
  - version-bump
  - uv
  - npm
  - s6-overlay
  - honcho
  - migration
---

# Migrating the hermes-agent wrapper image across a major Hermes overhaul (v2026.8.3 → v0.22.5)

> **No bump is routine.** Whenever the Hermes version is bumped in this repo, it requires a FULL review of all code and documentation changes — Hermes is known for shipping breaking changes in almost every update. Treat every version bump as a migration, never a one-line tag edit. This rule appears again under "Why This Matters" and "When to Apply" because it is the single most important takeaway from this migration.

## Context

This repository (`/home/taegost/_ws/hermes-agent`) maintains a thin Docker image that wraps the upstream `nousresearch/hermes-agent` base image for a long-running deployment. The image was pinned to hermes-agent v2026.8.3, which used date-versioned tags (for example `v2026.8.3`). Upstream moved to semver versioning with a major overhaul — the "PM" (package-management) rework — culminating in v0.22.5. The migration was merged as PR #1 (squash commit `1d51fa4` on `main`).

The bump looked like a tag swap. It was not. Upstream changed the versioning scheme, rebuilt the image around a multi-stage package-manager layout, replaced the toolchain (node 26 / npm 12), sealed the Python virtualenv, removed Honcho from the baked-in environment, and restructured process supervision. Each of these required a deliberate, verified change in the wrapper image. The migration only completed because every assumption was checked against BOTH the Hermes source AND the Hermes + Honcho documentation.

## Guidance

Process for any Hermes version bump in this repo, in order:

1. **Full review, every time.** Read all upstream code and documentation changes for the new version before touching the Dockerfile. Do not assume any prior behavior carries over. Hermes ships breaking changes in almost every update; treat no change as routine. Verify every fix against BOTH the Hermes source and the official Hermes + Honcho documentation. Where the two disagree or the docs admit doubt, trust the verified running install over the safest-looking reading of the docs. On one point in this migration (whether honcho had to be baked into the image), the safe reading of the documentation suggested baking it in, but the running install proved that runtime admission via `hermes plugins install` is the supported path.

2. **Check the version tag paradigm.** v2026.8.3 used date tags; v0.22.5 uses semver tags. The `FROM` line changes from a date tag to `nousresearch/hermes-agent:v0.22.5`. Confirm the tag scheme before assuming a newer tag of the old shape exists.

3. **Re-expose pm-pinned tools on PATH.** v0.22.x uses a multi-stage build. `uv` is no longer on PATH; the pm-pinned binary lives at `/opt/hermes/tools/uv-*/uv`. Fix with a symlink in the image:

   ```dockerfile
   RUN ln -s /opt/hermes/tools/uv-*/uv /usr/local/bin/uv
   ```

4. **Re-verify npm global installs under npm 12.** The base now ships node 26 with npm 12, which changed two behaviors that silently break global installs:
   - The default global prefix moved to the pm-managed node directory, which is not on PATH. Pass `--prefix /usr/local` to restore installs into `/usr/local/bin`.
   - npm 12 blocks postinstall scripts by default. Claude Code's postinstall fetches the platform-native binary, so the install fails without an explicit allowlist. Pass `--allow-scripts=@anthropic-ai/claude-code`.

   ```dockerfile
   RUN npm install -g --prefix /usr/local --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code
   ```

5. **Do not bake third-party Python tools into the base venv.** v0.22.x seals `/opt/hermes/.venv`. Never mutate it with raw `pip` or `uv` — `hermes pm repair` reverts any such change. Third-party tools such as `honcho-ai` are admitted at runtime instead: `hermes plugins install honcho` installs into `/opt/data/installs`, which sits on the persistent volume. The install survives container recreation and image updates.

6. **Keep the final `USER` as root.** The base image's s6 PID 1 bootstrap must run as root to chown and repair `/opt/data` ownership (via `cont-init.d` scripts); the supervised services then drop to the `hermes` user themselves. A trailing `USER hermes` broke the bootstrap — this was caught in PR review, not by the first smoke test. Add no `USER hermes` line at the end of the Dockerfile.

7. **Confirm tool-pinning decisions with the owner.** Claude Code stays UNPINNED by deliberate owner decision: `npm install -g @anthropic-ai/claude-code` pulls the latest version at each build. The owner rejected restoring the version pin despite repo history of pinning (auto memory [claude]: repo owner Mike must be consulted before design decisions such as install locations, version pinning, and paradigm choices; both `uv` and `claude` must resolve on PATH in the final image, and `@anthropic-ai/claude-code` stays unpinned). Do not silently change pinning policy during a bump.

8. **Smoke test the real entrypoint.** Boot the container through the actual entrypoint so s6 runs. Testing with `--entrypoint bash` bypasses s6 entirely and cannot see bootstrap failures such as the `/opt/data` ownership problem. This blind spot is why the `USER hermes` regression survived the first smoke test and was only caught in PR review.

9. **Deploy in three steps after the image swap.** Back up `/opt/data`, swap the image, then install the honcho plugin once (see the catalog caveat below). The plugin install is a one-time step per deployment because `/opt/data/installs` persists.

   **Catalog caveat (verified 2026-11-01):** at Hermes v0.22.5 the built-in plugin catalog pinned a honcho commit (`2108daf4`) that fails to install standalone — uv lock resolution exits 1 because the pinned commit's dependency groups reference `hermes-agent` as a workspace member. The fix exists upstream on honcho main but no re-pinned Hermes release had shipped. Until Hermes re-pins its catalog, bypass it with an explicit `--ref` to the fixed commit:

   ```bash
   docker exec <container> hermes plugins uninstall honcho   # only if a partial install exists
   docker exec <container> hermes plugins install honcho \
     --ref 6f91136b4e8d4b41de75f05d0cea822a1520b3a4 --yes-deps --enable
   ```

   A ref-pinned install does not track the catalog pin — it stays on that commit until explicitly changed, so re-check the pin after the next Hermes release.

## Why This Matters

- **No bump is routine.** Hermes is known for shipping breaking changes in almost every update. This migration changed versioning scheme, build layout, toolchain, venv policy, plugin policy, and process supervision at once. A bump treated as a tag edit would have produced an image where `uv` and `claude` are missing from PATH, global npm installs vanish, the venv mutates and gets reverted, and the container fails to boot.
- **Documentation can lag reality.** The Honcho point is the cautionary example: the safest reading of the Hermes + Honcho docs suggested baking honcho into the image, but the running install proved `hermes plugins install` (runtime admission into the persistent volume) is the supported path. Source verification plus a real install beat doc inference. Repeating the full review against both sources on every bump is the only reliable defense.
- **Entry-point-bypassing tests hide bootstrap bugs.** The `USER hermes` regression was invisible to a `--entrypoint bash` smoke test because s6 never ran. A passing smoke test that never booted PID 1 gave false confidence; only PR review caught it. Smoke tests must exercise the same startup path as production.

## When to Apply

- **Every Hermes version bump in this repo requires a FULL review of all code and documentation changes.** No bump is routine — Hermes ships breaking changes in almost every update. Apply this entire checklist each time, even for minor version increments.
- Whenever the base image's node/npm major version changes (prefix behavior, postinstall script blocking).
- Whenever adding third-party Python tooling to the environment — install at runtime via `hermes plugins install`, never into `/opt/hermes/.venv`.
- Whenever container boot fails after an image update — check the final `USER` directive and verify the smoke test actually ran s6, not `--entrypoint bash`.
- Whenever pinning policy (Claude Code, uv location) is in question — consult the owner before changing it (auto memory [claude]).

## Examples

Final merged Dockerfile (entire file, as merged in PR #1):

```dockerfile
FROM nousresearch/hermes-agent:v0.22.5
USER root

# Expose the pm-pinned uv on PATH.
RUN ln -s /opt/hermes/tools/uv-*/uv /usr/local/bin/uv

# Claude Code CLI, latest at build time.
RUN npm install -g --prefix /usr/local --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code
```

Deploy sequence after the image swap:

```bash
# 1. Back up the persistent volume.
# 2. Swap the image (recreate the container on the new tag).
# 3. Install honcho once into the persistent volume
#    (plain install fails on the broken v0.22.5 catalog pin — see the
#    catalog caveat in Prevention step 9 for the --ref workaround).
docker exec <container> hermes plugins install honcho \
  --ref 6f91136b4e8d4b41de75f05d0cea822a1520b3a4 --yes-deps --enable
```

Wrong versus right on the three easy-to-miss points:

```dockerfile
# WRONG: drops privileges before s6 bootstrap; bootstrap cannot chown/repair /opt/data.
USER hermes

# WRONG: prefix defaults to the pm-managed node dir (not on PATH); postinstall
# scripts are blocked, so the claude binary never fetches its native binary.
RUN npm install -g @anthropic-ai/claude-code

# WRONG: mutates the sealed venv; `hermes pm repair` reverts it.
RUN uv pip install --python /opt/hermes/.venv/bin/python honcho-ai
```

Smoke test shape — boot the real entrypoint and verify both tools resolve:

```bash
# Boots s6 PID 1 as production does; a `--entrypoint bash` run proves nothing
# about bootstrap ownership.
docker run -d --name smoke <image>
docker exec smoke which uv
docker exec smoke which claude
docker exec smoke claude --version
```

## Related

- [PR #1 — Bump Hermes Agent to v0.22.5, adapt image for new PM layout](https://github.com/Taegost/hermes-agent/pull/1) — the change this document describes (merged 2026-10-31).
- [Hermes Agent v0.22.5 release notes](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.5) — authoritative source for the package-management layout this migration adapts to.
- [NousResearch/hermes-agent#130715](https://github.com/NousResearch/hermes-agent/issues/130715) — s6-overlay lifecycle in the official Docker image; same s6 bootstrap contract that keeps derived images on USER root.
