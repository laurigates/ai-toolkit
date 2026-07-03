# Deploying AI Toolkit as a systemd service

`aitoolkit.service` runs the AI Toolkit web UI (Next.js + Prisma worker) on
`0.0.0.0:8675`, parallel to `comfyui.service` on `:8188`. The worker spawns
training jobs (`run.py`) as subprocesses, using the uv-managed `.venv`
interpreter resolved by `ui/cron/pythonPath.ts`.

## One-time setup

```sh
just sync          # build the cu128 .venv from uv.lock
just install-service   # ui-build + deploy the unit (prompts for sudo)
```

`install-service` runs `sudo cp` / `daemon-reload` / `enable --now`, so run it
in your own shell (it needs a password).

## Auth token

Set a UI password in the repo `.env` (loaded by the unit via `EnvironmentFile`):

```sh
# /mnt/sabrent/comfyui-workspace/ai-toolkit/.env
AI_TOOLKIT_AUTH=your-strong-token
```

`.env` is gitignored. Without it the UI runs unauthenticated.

## Day-to-day

| Action | Command |
|---|---|
| Restart | `just restart` (or `sudo systemctl restart aitoolkit.service`) |
| Logs | `just logs` |
| Status | `just status` |
| Rebuild UI after a code pull | `just ui-build && just restart` |
| Update Python deps | edit `pyproject.toml` → `just lock && just sync && just restart` |

## GPU coexistence with ComfyUI

Both services target the same RTX 4090. A training run and a ComfyUI
generation will contend for the 24 GB VRAM — stop one before a heavy run on
the other. The unit intentionally omits ComfyUI's `nvidia_uvm` modprobe
pre-step, which would disrupt a running `comfyui.service`.

## Design notes

- **PATH**: node from linuxbrew (`/home/linuxbrew/.linuxbrew/bin`) for the
  runtime; bun (package manager + script runner) is invoked by absolute path
  from mise. The training interpreter is resolved by explicit path, not PATH.
- **`bun run start`** assumes a prior build (`just ui-build`), so restarts are
  fast. `build_and_start` (the upstream one-shot) is only needed on first
  deploy — `install-service` handles it.
- **No auto-build on boot**: keeps restarts fast and deterministic. Re-run
  `just ui-build` after a UI change.
