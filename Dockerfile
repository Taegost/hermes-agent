FROM nousresearch/hermes-agent:v0.23.4
USER root

# Editor: nano, defaulted image-wide via EDITOR/VISUAL.
RUN apt-get update \
    && apt-get install -y --no-install-recommends nano \
    && rm -rf /var/lib/apt/lists/*

ENV EDITOR=nano VISUAL=nano

# Expose the pm-pinned uv on PATH.
RUN ln -s /opt/hermes/tools/uv-*/uv /usr/local/bin/uv

# Claude Code CLI, latest at build time.
RUN npm install -g --prefix /usr/local --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code
