#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Creating Python virtual environment..."
python3 -m venv .venv

echo "==> Activating venv and installing Ansible..."
source .venv/bin/activate
pip install -q -r requirements.txt

echo "==> Running Ansible playbook to deploy nv-monitor..."
ansible-playbook -i inventory/hosts.yml playbook.yml "$@"

echo "==> Done."
