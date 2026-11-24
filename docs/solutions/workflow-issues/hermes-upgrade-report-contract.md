---
title: "Hermes post-upgrade report contract (HERMES UPGRADE SUMMARY block)"
date: 2026-11-24
last_updated: 2026-11-24
category: workflow-issues
module: docker-image
problem_type: workflow_issue
component: documentation
severity: medium
applies_when:
  - "Reporting the outcome of any hermes-agent base image version bump"
  - "Reporting Hermes desktop app or Honcho backend/plugin upgrades"
  - "Writing smoke-test or post-rollout verification notes after a Hermes upgrade"
  - "Maintaining the upgrade LOG LINE ledger"
symptoms:
  - "Upgrade reports vary in shape between bumps, so regressions are noticed late or not at all"
  - "Unverified guesses in an upgrade report send the smoke test down the wrong path"
  - "No single ledger of prev-tag → new-tag transitions to diff against when something breaks later"
root_cause: missing_standard
resolution_type: standard
related_components:
  - development_workflow
  - documentation
  - smoke-test
tags:
  - hermes-agent
  - version-bump
  - reporting
  - smoke-test
  - upgrade
  - standard
---

# Hermes post-upgrade report contract (HERMES UPGRADE SUMMARY block)

> **Every post-upgrade report ends with the block.** No exceptions, no abbreviation. A guessed
> fact sends the smoke test down the wrong path; `UNKNOWN` sends it nowhere, which is safe.

## Context

This repo wraps the upstream `nousresearch/hermes-agent` image, and per
[migrate-hermes-agent-image-to-v0-22-5-pm-rework](migrate-hermes-agent-image-to-v0-22-5-pm-rework.md),
**no bump is routine** — Hermes ships breaking changes in almost every update. The natural
corollary: the report that closes out a bump must be uniform and complete, so that any
regression can be mapped to the exact transition that introduced it.

This contract defines the mandatory closing block for every post-upgrade report (upgrade PR,
deployment note, or session summary). It maps onto whatever report sections already exist —
add to them, don't drop them.

## The Contract

Every post-upgrade report must end with this block, filled from the reporter's own checks:

```
HERMES UPGRADE SUMMARY
Date (UTC): YYYY-MM-DD HH:MM
Previous image tag:
New image tag:
Hermes version (prev → new):
Desktop app version (if updated):
Honcho backend/plugin (if touched):

BREAKING CHANGES / DEPRECATIONS:
CONFIG & ENV (config.yaml/.env keys added/removed/renamed; how config reaches the agent):
FILESYSTEM & LAYOUT (mount points, paths moved, write permissions/restrictions, entrypoint):
PLUGINS & MEMORY (reinstalls needed, e.g. honcho; MEMORY.md / Honcho changes):
SKILLS (loading, validation, index behavior):
TOOLS & SURFACES (tools added/removed/renamed; Telegram / Desktop / dashboard / gateway):
BACKGROUND SYSTEMS (cron, kanban, delegation / subagents):
STATE & DATA (migrations, state.db, PVC/volume changes):
DEPLOYMENT (kubectl/helm commands verbatim; rollout status; pods healthy):
MANUAL STEPS STILL PENDING:
ALREADY VERIFIED BY YOU:
ERRORS IN LOGS:
REGRESSION WATCHLIST (top 3 things most likely broken):

LOG LINE: YYYY-MM-DD | <prev-tag> → <new-tag> | <desktop-ver> | <≤120-char notes>
```

## Rules for the block

- Fill every line; write `UNKNOWN` when unverified — never guess. A guessed fact sends the
  smoke test down the wrong path.
- Commands verbatim. One bullet per line, no prose. ≤ 400 words.
- Section with no changes → `none`.

## Notes

- The `LOG LINE` is a running ledger: one line per upgrade, kept across bumps, so any later
  regression can be correlated with the transition that plausibly caused it.
- The same contract is stored in the maintainer's Claude memory (`hermes-upgrade-report-contract.md`)
  and Honcho, so agent-generated upgrade reports follow it automatically.
