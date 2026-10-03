#!/usr/bin/env bash
set -euo pipefail
repository=${1:?repository path required}
port=${2:-8080}
export PATH="$HOME/.local/bin:$PATH"
# Linux and Windows must not share one virtual environment.
export UV_PROJECT_ENVIRONMENT="$HOME/.cache/touchmap-backend-venv"
export TOUCHMAP_STATE_DIR="$HOME/.local/state/touchmap"
cd "$repository/backend"
uv sync --frozen
exec uv run touchmap serve --host 127.0.0.1 --port "$port"
