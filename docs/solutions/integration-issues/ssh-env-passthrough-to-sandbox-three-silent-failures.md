---
title: "Restoring SSH environment passthrough from the Hermes agent to its sandbox (three stacked silent config failures)"
date: 2026-11-01
category: integration-issues
module: ssh-env-passthrough
problem_type: integration_issue
component: assistant
severity: high
symptoms:
  - "Environment variables from the agent's .env (ANTHROPIC_*, FIRECRAWL_*, GITHUB_TOKEN and peers) are absent inside sandbox SSH sessions"
  - "Tools running in the sandbox (Claude Code, Firecrawl, git push) have no API credentials and fail or run unauthenticated"
  - "AcceptEnv * baked into the sandbox image has no effect in the homelab-k8s deployment"
  - "The agent's ssh Host block (User, IdentityFile, Port, SendEnv) never applies to Hermes's own sessions"
  - "ssh -G resolves different effective configuration for the alias vs the FQDN Hermes actually dials"
root_cause: config_error
resolution_type: config_change
related_components:
  - tooling
  - development_workflow
tags:
  - ssh
  - sshd-config
  - sendenv
  - acceptenv
  - configmap
  - subpath-mount
  - env-passthrough
  - hermes-sandbox
---

# Restoring SSH environment passthrough from the Hermes agent to its sandbox (three stacked silent config failures)

## Problem

The Hermes agent pod forwards environment variables (ANTHROPIC_\*, FIRECRAWL_\*, GITHUB_TOKEN, and others) to the sandbox pod over SSH so tools like Claude Code running in the sandbox see the agent's configuration. The variables never appeared in sandbox sessions, even though an `AcceptEnv` setup had previously been reported as done and merged.

## Symptoms

- `.env` variables (`ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `FIRECRAWL_API_KEY`, `GITHUB_TOKEN`, etc.) were absent from shells in sandbox SSH sessions.
- Manual `ssh hermes-sandbox` checks from the agent pod appeared to pass, while Hermes's own connections transferred nothing — the test and the real traffic were matched by different config blocks.
- A previously "done" change (`AcceptEnv *` baked into the sandbox image) produced no observable effect at runtime.

## What Didn't Work

### Baking `AcceptEnv *` into the hermes-sandbox image (PR #3 there, `v1` tag)

The image change merged and was tagged, but had no runtime effect. The homelab-k8s Deployment `hermes-agent-sandbox` subPath-mounts a ConfigMap over `/etc/ssh/sshd_config`, so the sshd_config baked into the image via Dockerfile COPY is dead config — the mount always wins. The pod was also never restarted to confirm a rollout, so "done" rested on repo-merge evidence alone.

### Asserting "no ConfigMap exists"

During investigation it was claimed that no ConfigMap was involved, without reading the Deployment's `volumes`/`volumeMounts`. The ConfigMap not only existed and predated the work — it was the server configuration actually in effect at runtime, and it lacked `AcceptEnv`.

### Non-interactive smoke tests of the plugin installer

Earlier in the same session, smoke tests of the plugin installer ran non-interactively and therefore skipped the interactive prompt path entirely; artifact-level success was reported as runtime success. A separate failure, but the same underlying mistake: verifying the artifact instead of the runtime path.

## Solution

homelab-k8s PR #69, branch `update/rename-sandbox-sshd-configmap`. Four config changes plus a rollout:

1. **Rename the ConfigMap and its file** from `hermes-agent-sshd-config` to `hermes-sandbox-sshd-config`, and update the Deployment's volume pointer. The old name implied it configured the agent pod; it actually configures the sandbox's sshd. The runtime source of truth for sandbox sshd config is now unambiguous.

2. **Server half** — `AcceptEnv *` in the (renamed) ConfigMap, permitting the server to accept environment variables from the client.

3. **Client half** — an explicit per-variable `SendEnv` whitelist (one `SendEnv` line per variable) in `hermes-agent-ssh-config`: `SEARXNG_URL`, `FIRECRAWL_API_URL`, `FIRECRAWL_API_KEY`, `CANARY_SECRET`, `GITHUB_TOKEN`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY`, `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL`.

   Deliberately **not** sent: `API_SERVER_KEY`, `WEBHOOK_SECRET`, `OPENAI_API_KEY`, `HONCHO_API_KEY`. Every forwarded variable is readable by any code running in the sandbox, so each entry in the whitelist is an owner-level forwarding decision, made per variable.

4. **Host pattern widened** so the config block applies to the hostname Hermes actually uses:

   ```sshconfig
   Host hermes-sandbox hermes-sandbox.hermes-agent.svc.cluster.local
       User hermes
       IdentityFile ~/.ssh/id_ed25519
       Port 22
       SendEnv SEARXNG_URL
       SendEnv FIRECRAWL_API_URL
       SendEnv FIRECRAWL_API_KEY
       # ... one SendEnv line per whitelisted variable
   ```

5. **Rollout** — restart the sandbox Deployment so sshd loads the renamed ConfigMap.

Permissive `AcceptEnv *` server-side is acceptable here because the client whitelists what it sends and the sshd has exactly one trusted, key-authenticated caller.

### Security review notes

`SendEnv *` was used initially and then replaced with the explicit whitelist, because the agent pod's environment contains its own secrets that must not leak into the sandbox. CodeRabbit flagged `FIRECRAWL_API_KEY` during review; the owner declined removal (read-only key, required by Claude Code inside the sandbox). The disposition records the policy: what gets forwarded is owner policy, decided per variable — not a blanket rule.

### Verification

`ssh -G -F <extracted-config> <host>` was run for **both** the alias and the FQDN; both resolved identically (user `hermes`, port 22, identityfile, `sendenv` active). Pre-fix, the FQDN resolved to local defaults, which is exactly what the Host-pattern bug predicted. Production confirmed by the owner end-to-end: passthrough working.

## Why This Works

Env passthrough failed because of three independent silent failure modes. Any one of them alone defeats it, and all three were present simultaneously — which is why each partial fix appeared to do nothing.

1. **Mount masking.** A subPath ConfigMap mount over `/etc/ssh/sshd_config` replaces the image's baked file completely. The Dockerfile `COPY` of an sshd_config containing `AcceptEnv *` looked like a completed change in the repo but never executed at runtime, because Kubernetes volume mounts are applied after the image filesystem is in place. The ConfigMap — which lacked `AcceptEnv` — was the real server config all along, and it was also misnamed as the agent's config when it is the sandbox's.

2. **Missing client half.** `AcceptEnv` is server-side *permission only*. OpenSSH clients send no environment variables unless the client config says `SendEnv`. Permission to receive without instruction to send transfers nothing.

3. **Host pattern mismatch.** The client config keyed on `Host hermes-sandbox`, but Hermes connects using the FQDN `hermes-sandbox.hermes-agent.svc.cluster.local` (its `ssh_host` in `/opt/data/config.yaml`; see homelab-k8s `docs/solutions/runtime-errors/hermes-agent-ssh-config-param-rename.md`). OpenSSH matches `Host` patterns against the command-line hostname, so the entire block — `User`, `IdentityFile`, `Port 22`, and any `SendEnv` — silently never applied to Hermes's sessions. Manual `ssh hermes-sandbox` tests passed because they used the alias, which matched the block: a test blind spot that made the broken setup look healthy.

The fix works because it addresses all three layers: the runtime server config (renamed ConfigMap, no longer masked, now containing `AcceptEnv *`), the client send list (per-variable `SendEnv`), and the match key (both hostname forms in one `Host` pattern). `ssh -G` resolved identically for alias and FQDN only once all three were correct, and the owner's live `env` check confirmed the end-to-end path.

## Prevention

**Verify the runtime path, never the artifact.** Twice this session a runtime capability was declared working from artifact-level evidence (file in image / PR merged) without exercising the runtime path. A file baked into an image can be masked by a mount; a merged PR can still be sitting unrolled. Rules:

1. **Before claiming an sshd config change works, check what actually serves the file.** Read the Deployment's `volumes`/`volumeMounts` before reasoning about any config file inside a container. If a ConfigMap, Secret, or subPath mounts over the path, the image's copy is dead config and the mount is the source of truth. The claim "no ConfigMap exists" must never be made without reading the mount list.

2. **Run `ssh -G` for every hostname form actually used.** After any SSH client config change:

   ```bash
   ssh -G -F <config> hermes-sandbox
   ssh -G -F <config> hermes-sandbox.hermes-agent.svc.cluster.local
   ```

   Diff the output. If a hostname form used by the real caller is missing from the test, the `Host` block's application is unverified. Note that `SendEnv` lines appear in `ssh -G` output as `sendenv`, which makes this the cheap static half of the check.

3. **Finish with a live `env` check in the target session.** `ssh -G` proves config resolution, not transfer. The closing verification for passthrough work is a real SSH session into the sandbox running `env | grep -E 'ANTHROPIC|FIRECRAWL|GITHUB'` and confirming the expected variables are present.

4. **Test with the caller's invocation, not a convenient alias.** A manual `ssh hermes-sandbox` from a shell exercises a different match path than the application's FQDN connection. When the manual test passes but the integration fails, suspect hostname matching first.

5. **Interactive paths need interactive tests.** A smoke test that skips a prompt (non-interactive mode) verifies only the non-interactive path. If the feature includes an interactive branch, that branch needs its own exercise before "working" is claimed.

6. **Treat env forwarding as an owner-approved per-variable list.** Never `SendEnv *` from a pod whose environment contains secrets. Add each variable explicitly, and record any reviewer flag (e.g., CodeRabbit on `FIRECRAWL_API_KEY`) together with the owner's disposition so the forwarding set stays a documented policy rather than an accident of history.

## Related

- **homelab-k8s `docs/solutions/conventions/hermes-agent-ssh-sandbox-deployment-pattern.md`** — the cluster-side convention doc for this deployment; canonical statement of the both-halves rule (`SendEnv` + `AcceptEnv`) and of the ConfigMap-over-image source-of-truth fact, updated in the same PR #69. This doc extends that guidance from the image side of the boundary and does not supersede it.
- **homelab-k8s PR #69** (`update/rename-sandbox-sshd-configmap`, merged 2026-11-01) — the implementing change: ConfigMap rename, `AcceptEnv *`, 13-variable `SendEnv` whitelist, widened Host pattern, plus a pre-commit fix (validator scripts now include staged renames, `--diff-filter=ACMR`).
- **homelab-k8s `docs/solutions/runtime-errors/hermes-agent-ssh-config-param-rename.md`** — evidence that Hermes dials the FQDN (`ssh_host` in `/opt/data/config.yaml`), the fact that made failure mode 3 possible.
- **hermes-sandbox PR #3** — the image-side `AcceptEnv *` change that mount masking silently defeated.
- **`docs/solutions/workflow-issues/migrate-hermes-agent-image-to-v0-22-5-pm-rework.md`** — sibling boundary lesson: the wrapper image is not the source of truth for runtime behavior (sealed venv, runtime plugins); this doc extends the same boundary to sshd_config.
