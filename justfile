# AI Toolkit (laurigates fork) — task recipes.
# Python env is uv-managed (pyproject.toml + uv.lock); the UI is Next.js.

# uv cache lives on the big disk; root partition is small on this host.
export UV_CACHE_DIR := "/mnt/sabrent/uv-cache"

_default:
    @just --list

# --- Python (uv) -----------------------------------------------------------

# Re-resolve the lockfile after editing pyproject.toml dependencies.
lock:
    uv lock

# Create/update the uv-managed .venv from uv.lock (cu128 torch stack).
sync:
    uv sync

# Run a CLI training job: `just train config/whatever.yaml`
train config:
    uv run python run.py {{config}}

# --- UI (Next.js + Prisma worker) ------------------------------------------

# Install UI deps, push the Prisma schema, and build (required before `start`).
ui-build:
    cd ui && bun install && bun run update_db && bun run build

# Run the UI in the foreground on :8675 (what the systemd unit runs).
ui-start:
    cd ui && bun run start

# --- systemd service -------------------------------------------------------

# Deploy the unit and (re)start it. Needs sudo — run this recipe yourself:
#   just install-service
# (sudo cp / daemon-reload / enable prompt for a password.)
install-service: ui-build
    sudo cp deploy/aitoolkit.service /etc/systemd/system/aitoolkit.service
    sudo systemctl daemon-reload
    sudo systemctl enable --now aitoolkit.service
    @echo "aitoolkit.service deployed on http://0.0.0.0:8675"

restart:
    sudo systemctl restart aitoolkit.service

status:
    systemctl status aitoolkit.service --no-pager

logs:
    journalctl -u aitoolkit.service -f

# --- upstream sync ---------------------------------------------------------

# Pull ostris/ai-toolkit main into this fork's working branch.
sync-upstream:
    git fetch upstream
    @echo "Now merge/rebase: git merge upstream/main  (or  git rebase upstream/main)"
