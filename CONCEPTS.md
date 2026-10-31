# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ts-compound and ts-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Hermes Wrapper Image

### Wrapper image
The thin Docker image this repository builds on top of the upstream Hermes Agent base image. It carries deployment-specific additions (PATH symlinks, global CLIs) and nothing else; behavior changes belong upstream or in runtime configuration, not baked into it.

### PM (package management)
Hermes's subsystem that owns installation of runtimes and third-party tooling. It treats the shipped Python environment as sealed, reverts manual mutations on repair, and admits third-party tools as runtime plugins that install into the persistent data volume rather than the image.

### Sealed venv
The Python environment Hermes ships inside its image, treated as immutable by the package manager — direct modification is reverted at repair time. Third-party Python tools are never installed into it; they are admitted as runtime plugins instead.

### s6 bootstrap
The container's first startup phase, in which the PID 1 supervisor runs as root to repair ownership of the persistent data directory before starting services, which then drop to the unprivileged service user themselves. Derived images must not drop the runtime user before this phase completes.

### Persistent data volume
The storage mounted into the Hermes container that carries state and plugin installs across container recreation and image updates. Anything written here survives upgrades, which is what makes one-time post-deploy steps sufficient.
