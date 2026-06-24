FROM nousresearch/hermes-agent:v2026.6.19
USER root
RUN uv pip install --python /opt/hermes/.venv/bin/python3 honcho-ai
USER hermes
