FROM nousresearch/hermes-agent:v0.22.5
USER root

# Expose the pm-pinned uv on PATH.
RUN ln -s /opt/hermes/tools/uv-*/uv /usr/local/bin/uv

# Claude Code CLI, latest at build time.
RUN npm install -g --prefix /usr/local --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code
