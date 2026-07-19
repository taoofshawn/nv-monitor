#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Ensure uv is available
if ! command -v uv &>/dev/null; then
    echo "==> Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Source it for this session
    if [ -f "$HOME/.cargo/env" ]; then
        . "$HOME/.cargo/env"
    fi
fi

echo "==> Creating Python virtual environment with uv..."
uv venv

echo "==> Installing Ansible with uv..."
uv pip install -r requirements.txt

echo "==> Running Ansible playbook to deploy nv-monitor..."
uv run ansible-playbook -i inventory/hosts.yml playbook.yml "$@"

echo "==> Done."
