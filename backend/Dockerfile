FROM python:3.12.11-slim
COPY --from=ghcr.io/astral-sh/uv:0.9.2 /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock ./
COPY touchmap ./touchmap
RUN uv sync --frozen --no-dev && useradd --create-home touchmap && mkdir /state && chown touchmap /state
USER touchmap
ENV TOUCHMAP_STATE_DIR=/state
EXPOSE 8787
CMD ["uv", "run", "--frozen", "touchmap", "serve"]
