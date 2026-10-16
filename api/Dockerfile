# Pixorex API image: one uvicorn process per container; scale with more containers
# (FastAPI deployment docs). Used for both the API and the one-shot migration job.

FROM python:3.12-slim AS builder
COPY --from=ghcr.io/astral-sh/uv:0.13.1 /uv /bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_NO_DEV=1 UV_PYTHON_DOWNLOADS=0
WORKDIR /app
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project

FROM python:3.12-slim
RUN useradd --system --uid 10001 --no-create-home pixorex
WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY app ./app
COPY migrations ./migrations
COPY alembic.ini ./
COPY scripts ./scripts
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1
USER pixorex
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --retries=5 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/v1/health', timeout=2)"]
# asyncio loop, not uvloop: uvloop resolves host names on only 4 threads, so while a dependency
# is missing its slow lookups block the others and /ready reports healthy services as "fail".
CMD ["uvicorn", "--factory", "app.main:create_app", "--host", "0.0.0.0", "--port", "8000",      "--loop", "asyncio", "--no-server-header"]
