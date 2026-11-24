---
title: "feat: Add nano editor and bump base to hermes-agent v0.23.4"
type: feat
date: 2026-11-24
---

# feat: Add nano editor and bump base to hermes-agent v0.23.4

## Summary

Add `nano` to the wrapper image (with `EDITOR`/`VISUAL` defaulted to it) and bump the base image from `nousresearch/hermes-agent:v0.22.5` to `v0.23.4`, executed as a full migration review per the repo's bump-migration learning — never a tag edit.

---

## Problem Frame

The wrapper image ships no editor, so anything running in the container that wants one (interactive git commits, tool prompts) has nothing to fall back on. Separately, the base pin (v0.22.5, released 2026-10-23) is five stable releases behind; the window to v0.23.4 includes a High-severity fix for Docker/SSH terminal backends (GHSA-p22p-9ph6-gmrh / CVE-2026-130164, fixed in v0.23.2) and the plugin-catalog live-fetch fix (v0.23.1) that unblocks the honcho catalog pin workaround documented in the migration learning.

This repo's standing rule (`docs/solutions/workflow-issues/migrate-hermes-agent-image-to-v0-22-5-pm-rework.md`): Hermes ships breaking changes in almost every update, so every bump requires full review of upstream changes and re-verification of every wrapper assumption.

#### ProblemFrame.D1. GHSA fix attributed to v0.23.2, not v0.23.3
**Decision:** The High-severity terminal-backend fix (GHSA-p22p-9ph6-gmrh / CVE-2026-130164) is dated v0.23.2 in Problem Frame, U2 step 1, and Sources.
**Why:** The initial draft said v0.23.3. The advisory's fixed commit (ae2a81ccc00) is v0.23.2's release commit, and the fix appears in the v0.23.2 release notes — re-verified against the fetched notes before applying.
**Source:** review agent Adversarial, 2026-11-24 doc-review, auto-applied after orchestrator verification

#### ProblemFrame.D2. Pin-age claim corrected to release date
**Decision:** The pin is described as "v0.22.5, released 2026-10-23, five stable releases behind" instead of "two months behind".
**Why:** v0.22.5 shipped 2026-10-23 and the repo pinned it 2026-10-31 (PR #1); the gap to v0.23.4 is ~4.5 weeks. The release count carries the staleness argument; the inflated duration distorted urgency.
**Source:** review agents Adversarial + Feasibility + Documentation (merged), 2026-11-24 doc-review, auto-applied

---

## Requirements

**Image tooling**

- R1. `nano` is present and resolvable on PATH in the built image.
- R2. `EDITOR=nano` and `VISUAL=nano` are set image-wide, so editor-launching tools default to nano.
- R3. The nano layer stays slim (no recommends, apt lists cleaned).

**Version bump**

- R4. Base image is `nousresearch/hermes-agent:v0.23.4`, as an explicit version tag.
- R5. Migration-checklist verifications pass on the new base before merge: uv resolves on PATH, claude resolves and reports a version, s6 bootstrap boots with the final `USER root`, nano still present with env vars intact, honcho plugin loads.
- R6. Smoke testing boots the real entrypoint (s6 as PID 1), not an `--entrypoint bash` bypass.

#### Requirements.D1. R5 (migration-checklist verifications) extended with honcho
**Decision:** R5 now requires the honcho plugin to load, alongside uv/claude/nano/env checks.
**Why:** The persistence claim came from the v0.22.5-era learning and is untested across a runtime-major change; a green smoke test that skips honcho would not prove the deployment's memory plugin works.
**Source:** user, 2026-11-24 approved review agent Adversarial's proposal in doc-review walk-through

---

## Key Technical Decisions

- KTD1. Install nano with `apt-get` in the Dockerfile: base is Debian 13 (trixie) with apt-get, and nano was verified absent in v0.22.5. Use `--no-install-recommends` and clean `/var/lib/apt/lists` in the same layer (R3).
- KTD2. Set `ENV EDITOR=nano VISUAL=nano` in the image rather than only shipping the binary: user decision (2026-11-24) — tools that launch an editor should default to it instead of failing to find one. This is an owner-approved exception to CONCEPTS.md's Wrapper-image scope clause ("behavior changes belong upstream or in runtime configuration, not baked into it"); CONCEPTS.md is amended on landing (see Operational Notes).
- KTD3. Bump target is v0.23.4, not the floating `stable` tag and not v0.23.3: user decision (2026-11-24). It is what the `stable` channel tracks, carries the CVE and catalog fixes, and keeps the repo's explicit-pin convention (Hermes pinned, Claude Code unpinned).
- KTD4. The bump is executed as a full migration review following the learning's checklist, not a tag edit: upstream is known to break image layout, toolchain, and supervision contracts without announcement.
- KTD5. Keep the final `USER root` and add no `USER hermes`: the s6 bootstrap must chown/repair `/opt/data` before services drop privileges.
- KTD6. Claude Code stays unpinned (standing owner decision; see migration learning step 7). Do not change pinning policy during this bump.

#### KTD2.D1. KTD2 (image-wide EDITOR/VISUAL) recorded as a CONCEPTS.md scope exception
**Decision:** KTD2 cites CONCEPTS.md's Wrapper-image scope clause ("behavior changes belong upstream or in runtime configuration, not baked into it") as an owner-approved exception, and Operational Notes carry the task to amend CONCEPTS.md's definition on landing.
**Why:** Without this, the repo's only written definition of the wrapper image's scope goes false when the plan lands, and the exception survives only in an archived plan. The owner's ENV decision stands — the record is reconciled, not the decision reversed.
**Source:** user, 2026-11-24 approved review agent Documentation's proposal in doc-review walk-through

---

## Implementation Units

### U1. Add nano and editor env to the wrapper image

**Goal:** The built image ships nano as its editor, defaulted via environment.
**Requirements:** R1, R2, R3.
**Dependencies:** none — lands on the current v0.22.5 base if executed before U2.
**Files:** `Dockerfile`
**Approach:** One `RUN` layer after the existing `USER root`: apt-get update, install nano with `--no-install-recommends`, remove `/var/lib/apt/lists/*` in the same layer. One `ENV` line setting `EDITOR=nano` and `VISUAL=nano`.
**Patterns to follow:** Layer hygiene mirrors the existing single-purpose `RUN` style of the current Dockerfile.
**Test scenarios:**

- Happy path: `docker build` succeeds on the current base.
- Happy path: `nano --version` succeeds in the built image (via `--entrypoint`, this check needs no s6).
- Happy path: `env` in the built image shows `EDITOR=nano` and `VISUAL=nano`.
- Edge case (R3): `/var/lib/apt/lists` in the built image contains no package indexes (only `lock`/`partial`).

**Verification:** Built image passes the four checks above.
**Test expectation note:** image-build config; the checks above are the verification — no test suite applies.

#### U1.D1. R3 (slim-layer requirement) made falsifiable
**Decision:** U1 gained a fourth test scenario: `/var/lib/apt/lists` in the built image contains no package indexes (only `lock`/`partial`).
**Why:** Every other requirement paired with an explicit check; without this one, a later edit dropping the apt-lists cleanup would pass verification unnoticed.
**Source:** user, 2026-11-24 approved review agent Test-documentation's proposal in doc-review walk-through

### U2. Bump base image to v0.23.4 with full migration review

**Goal:** Base image is v0.23.4 with every wrapper assumption re-verified, per the migration learning.
**Requirements:** R4, R5, R6.
**Dependencies:** U1 (nano layer) — re-verify its checks on the new base.
**Files:** `Dockerfile`
**Approach:** Read first, then touch the Dockerfile — the learning's rule.

1. Re-read release notes v0.23.0 → v0.23.4 for image-layout changes. Known so far: v0.23.0 ships the Webapp bundle in the image and adds tmux plus Office/PDF libraries (image grows); v0.23.1 raises the catalog size cap (live catalog honored again); v0.23.2 fixes GHSA-p22p-9ph6-gmrh (PR #154487). Curated notes for the v0.23.1+ window ship with v0.24.0 — treat the v0.23.0 "Hearth" notes as the full curated baseline and re-scan patch-note rollups for image-relevant entries.
2. Pull v0.23.4 and verify the learning's full assumption set against the image before editing the Dockerfile — do not rely on release notes, which omit most window changes on purpose: `/opt/hermes/tools/uv-*` still exists (adjust the symlink glob if the layout moved), sealed venv intact at `/opt/hermes/.venv`, `hermes plugins` subcommands present and `/opt/data/installs` layout unchanged, s6 `cont-init.d` scripts present, npm prefix and postinstall-allowlist behavior unchanged (node/npm majors unchanged or re-derive the `--prefix /usr/local` and `--allow-scripts` flags per learning step 4), Debian base still apt-based (nano layer from U1 still valid).
3. Only then change `FROM` to `nousresearch/hermes-agent:v0.23.4`. Keep final `USER root` (KTD5). Change nothing about Claude Code pinning (KTD6).
4. Build and smoke test through the real entrypoint so s6 runs as PID 1: container reaches running state, `uv` and `claude` resolve, `claude --version` prints, `nano --version` prints, env vars intact, and `hermes plugins list` shows honcho present and enabled — a ref-pinned install resolved against v0.22.5 may fail under v0.23.x, so if it does, reinstall per the learning's catalog caveat before declaring the bump verified.

**Patterns to follow:** The checklist in `docs/solutions/workflow-issues/migrate-hermes-agent-image-to-v0-22-5-pm-rework.md` (steps 1–8).
**Test scenarios:**

- Happy path: build succeeds on v0.23.4 with the U1 layer included.
- Happy path: smoke boot via real entrypoint reaches running state (s6 bootstrap completes — catches `/opt/data` ownership regressions an `--entrypoint bash` run cannot see).
- Happy path: `uv`, `claude`, and `nano` all resolve on PATH in the running container; `claude --version` succeeds.
- Edge case: if `/opt/hermes/tools/uv-*` moved in v0.23.x, locate the new pm-pinned uv path and update the symlink rather than dropping it.
- Error path: if the image fails to build or boot, stop and record findings before proceeding — do not merge a partially verified bump.

**Verification:** All checks above pass on the built v0.23.4 image; migration learning checklist walked end to end.

#### U2.D1. Pre-build verification extended to the learning's full assumption set
**Decision:** U2 step 2 empirically checks sealed venv (`/opt/hermes/.venv`), `hermes plugins` subcommands and `/opt/data/installs` layout, s6 `cont-init.d` scripts, and npm prefix/postinstall-allowlist behavior against the pulled image — not just uv path, node majors, and Debian base.
**Why:** The bump window is ~5,100 merged PRs and every patch release leaves its changes "undocumented on purpose" until v0.24.0, so release notes cannot carry the review; the plan's own Sources had already shown that failure mode (v0.23.2 missing, the security fix misdated). Empirical checks don't depend on upstream documenting anything.
**Source:** user, 2026-11-24 approved review agent Adversarial's proposal in doc-review walk-through

#### U2.D2. Honcho load check added to the smoke list
**Decision:** U2 step 4 requires `hermes plugins list` to show honcho present and enabled, with reinstall per the learning's catalog caveat on failure, before the bump is declared verified.
**Why:** The ref-pinned install was resolved against v0.22.5 dependency groups and may fail under v0.23.x; without this check the failure surfaces days later as missing memory, not at smoke time.
**Source:** user, 2026-11-24 approved review agent Adversarial's proposal in doc-review walk-through

---

## Scope Boundaries

**Out of scope**

- Other editors (vim, etc.) — nano only, per request.
- Claude Code pinning changes — standing owner decision keeps it unpinned.
- Honcho plugin work beyond the post-swap catalog re-check in Operational Notes.
- Enabling the Webapp (`webapp.enabled` is runtime config, off by default; not an image concern).

### Deferred to Follow-Up Work

- Re-read the v0.24.0 curated release notes when they ship (they document the full v0.23.x window) and confirm nothing image-relevant was missed by the patch-note rollups.

---

## Risks & Dependencies

- v0.23.4 released today (2026-11-24) — least field exposure of any stable. Mitigation: full review + smoke test; rollback is reverting the `FROM` tag and restoring `/opt/data` from the pre-swap backup taken in deploy step 1 (v0.23.x bootstrap and storage changes may have mutated the volume).
- v0.23.0 changed image contents (Webapp bundle, tmux, Office/PDF libs) — image grows and silent layout shifts are possible; mitigated by U2 step 2's pre-build verification against the pulled image.
- Setting `EDITOR=nano` image-wide changes failure modes: a tool spawning `$EDITOR` without a TTY now hangs in nano where it previously errored on a missing editor. Accepted with KTD2. Mitigation: override per run (`docker run -e EDITOR=` / compose environment) needs no rebuild; revisit the image default if agent-driven flows stall.
- Honcho catalog/pin drift after the swap — see Operational Notes.

#### Risks.D1. Risk mitigation step reference corrected
**Decision:** The image-content risk bullet cites U2 step 2's (pre-build verification against the pulled image), not step 3's, as its mitigation.
**Why:** Step renumbering during plan editing left the risk pointing at the `FROM`-edit step; a reader auditing the mitigation landed on the wrong step.
**Source:** review agent Coherence, 2026-11-24 doc-review, auto-applied

#### Risks.D2. Rollback includes volume restore
**Decision:** Rollback for the release-day risk is reverting the `FROM` tag AND restoring `/opt/data` from the pre-swap backup taken in deploy step 1.
**Why:** Booting any image mutates `/opt/data` (bootstrap chown/repair), and the window includes a storage-layer rework (v0.23.3 persistence-interface split with SQLite backend) — reverting only the tag could reboot onto a migrated volume, turning a bad deploy into data loss with a usable backup unused.
**Source:** user, 2026-11-24 approved review agent Adversarial's proposal in doc-review walk-through

---

## Documentation / Operational Notes

Deploy sequence after the image swap (from the migration learning):

```bash
# 1. Back up the persistent volume (/opt/data).
# 2. Swap the image (recreate the container on the new tag).
# 3. Honcho plugin persists in /opt/data/installs — no reinstall needed.
```

Post-swap, unconditionally verify honcho: `hermes plugins list` shows honcho enabled and a plugin invocation succeeds. v0.23.1+ honors the live catalog again, so if the deployment still runs the ref-pinned commit, optionally move it to the catalog pin and re-verify (`hermes plugins update honcho` — subcommand unverified against the learning, which documents only install/uninstall; reinstall without `--ref` is the documented path). Keep the `--ref` fallback in mind if the catalog pin is still broken.

After landing, update the docs: amend CONCEPTS.md's Wrapper-image definition to include default editor environment (KTD2's owner-approved exception), and update the migration learning doc's catalog caveat (or add a short v0.23.4 note) via the usual solutions flow — the `--ref` guidance is version-stale once v0.23.4 is deployed.

---

## Sources & Research

- `docs/solutions/workflow-issues/migrate-hermes-agent-image-to-v0-22-5-pm-rework.md` — the bump checklist this plan follows; source of USER-root, npm flags, sealed-venv, and catalog constraints.
- GitHub releases `NousResearch/hermes-agent` v0.22.5 → v0.23.4 (fetched 2026-11-24): v0.23.0 "Hearth" notes (Webapp in Docker image, tmux + Office/PDF libs added), v0.23.1 catalog cap fix (#151860), v0.23.2 GHSA-p22p-9ph6-gmrh fix (PR #154487), v0.23.3 and v0.23.4 rollups (curated notes deferred to v0.24.0).
- Docker Hub `nousresearch/hermes-agent` tags (fetched 2026-11-24): `v0.23.4` = `stable` = `latest`, published 2026-11-24T08:17Z.
- Local inspection of `nousresearch/hermes-agent:v0.22.5`: Debian 13 (trixie), `/usr/bin/apt-get`, nano absent.

#### Docs.D1. Post-swap honcho verification made unconditional; CONCEPTS.md amendment task added
**Decision:** Operational Notes require an unconditional post-swap honcho verify (`hermes plugins list` shows honcho enabled, plugin invocation succeeds) regardless of `--ref` pin or catalog pin, and add the post-landing doc tasks: amend CONCEPTS.md's Wrapper-image definition (KTD2 exception) and refresh the migration learning's catalog caveat.
**Why:** The verify previously lived only in the optional catalog-move branch, leaving the plan's stated fallback (keep `--ref`) with no post-swap check; the CONCEPTS.md task keeps the corpus matching the image after landing.
**Source:** user, 2026-11-24 approved review agent Test-documentation's proposal in doc-review walk-through
