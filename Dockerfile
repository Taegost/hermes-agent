FROM nousresearch/hermes-agent:v2026.6.19
USER root
RUN uv pip install --python /opt/hermes/.venv/bin/python3 honcho-ai

# Install Claude Code CLI (pinned to latest as of 2026-06-28)
RUN npm install -g @anthropic-ai/claude-code@2.1.195

USER hermes
