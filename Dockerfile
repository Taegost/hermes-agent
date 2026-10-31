FROM nousresearch/hermes-agent:v0.22.5
USER root

# uv is no longer on PATH in the v0.22.x runtime image (multi-stage build);
# expose the pm-pinned binary from the managed tools store.
RUN ln -s /opt/hermes/tools/uv-*/uv /usr/local/bin/uv

# honcho-ai is NOT baked in: since v0.22.x, Hermes admits it at runtime via
# `hermes plugins install honcho`; PM installs it into /opt/data/installs
# (persistent volume), where it survives container recreation and image
# updates. Mutating /opt/hermes/.venv with raw uv/pip is forbidden by the
# Hermes package-management docs and would be dropped by `hermes pm repair`.

# Install Claude Code CLI (latest at build time).
# --prefix /usr/local restores the pre-v0.22 install location: npm's default
# global prefix is now the pm-managed node in /opt/hermes/tools, whose bin
# dir is not on PATH.
# npm 12 blocks postinstall scripts by default; claude-code needs its
# postinstall to fetch the platform-native binary.
RUN npm install -g --prefix /usr/local --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code

# No trailing USER directive: the base image runs s6-overlay as root so
# cont-init.d can repair /opt/data ownership on boot; the supervised Hermes
# services drop to the hermes user themselves (s6-rc.d/*/run).
# Ending on USER hermes made PID1 uid 10000 and broke that bootstrap.
