# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## This is a fork

`laurigates/ai-toolkit`, forked from `ostris/ai-toolkit` (tracked as the
`upstream` remote). This fork's divergence is **operational, not functional**:
modern Python packaging (uv + `pyproject.toml`) and an installable systemd
service. The training/UI code is upstream's — prefer contributing fixes to
that code upstream, and pull upstream changes with `just sync-upstream` (then
`git merge upstream/main`).

- `pyproject.toml` + `uv.lock` are the **source of truth** for the Python env.
- `requirements.txt` / `requirements_base.txt` are retained **only** as the
  upstream-sync surface — don't treat them as canonical, but keep them roughly
  in step when adding deps so upstream merges stay clean.
- **Version lives in two places now**: `version.py` (`VERSION`, what the app
  reports via `info.py`) and `pyproject.toml` (`[project] version`). Keep them
  in sync; there is no release-please automation here.

## Commands

Python env is uv-managed; recipes live in the `justfile` (`just` to list).

| Task | Command |
|---|---|
| Build/refresh the venv (cu128 torch stack) | `just sync` (`uv sync`) |
| Re-resolve lockfile after editing deps | `just lock` (`uv lock`) |
| Run a training job (CLI) | `just train config/whatever.yaml` → `uv run python run.py <config>` |
| Run any Python | `uv run python …` (or `.venv/bin/python …`) |
| Build the UI | `just ui-build` (npm install + `prisma db push` + next build) |
| Run the UI on :8675 | `just ui-start`, or the systemd service (below) |
| Deploy/restart the systemd service | `just install-service` (needs sudo) / `just restart` |

- **uv cache is redirected to `/mnt/sabrent/uv-cache`** (via the `justfile`'s
  `UV_CACHE_DIR` export) because this host's root partition is small. Set it
  when running `uv` outside the recipes.
- **No pytest suite.** `testing/` and `ui_scripts/test_script.py` are ad-hoc
  scripts, not a runnable test tier. "Testing" a change means running a real
  training/generate job against a small config.
- torch/torchvision/torchaudio are pinned (`2.9.1`/`0.24.1`/`2.9.1`) and
  resolved through the `pytorch-cu128` index declared in `pyproject.toml`;
  `diffusers` is git-pinned via `[tool.uv.sources]`. Don't add a bare `torch`
  dep — it will pull a non-cu128 wheel.

## Architecture

### Config-driven job dispatch (the core loop)

Everything runs from a **YAML config**, not code paths. `run.py` →
`toolkit/job.py:get_job(config)` reads the config's top-level `job:` field and
instantiates a job class from `jobs/`:

| `job:` | Class | Purpose |
|---|---|---|
| `extension` | `ExtensionJob` | **The common one** — runs one or more extension "processes" |
| `train` | `TrainJob` | Direct training |
| `extract` | `ExtractJob` | Extract a LoRA/LoCon from a model |
| `mod` | `ModJob` | Modify/rescale an existing LoRA |
| `generate` | `GenerateJob` | Inference/sampling |

A job runs a list of **processes** (`config.process[]`), each with a `type`.
For `job: extension`, `type` is an **extension uid** (e.g. `sd_trainer`,
`ui_trainer`, `diffusion_trainer`). This indirection is why most real training
configs say `job: extension` + `type: sd_trainer` rather than `job: train`.

### Extension registry

`toolkit/extension.py` scans two folders — `extensions/` (user) and
`extensions_built_in/` (shipped) — importing each subpackage and reading its
`AI_TOOLKIT_EXTENSIONS` list. Each entry is an `Extension` subclass with a
unique `uid` and a `get_process()` returning the process class. To add a
capability, drop a package in `extensions/` exposing `AI_TOOLKIT_EXTENSIONS`;
no core edits needed. The workhorse trainer is `extensions_built_in/sd_trainer`
(uids `sd_trainer` / `ui_trainer` / `diffusion_trainer` /
`textual_inversion_trainer`), which subclasses `jobs/process/BaseSDTrainProcess.py`.

### Process base classes

`jobs/process/` holds the base classes the extensions build on —
`BaseSDTrainProcess` (the main training loop: dataloader, bucketing, EMA,
sampling, checkpointing), plus `BaseExtractProcess`, `BaseMergeProcess`,
`GenerateProcess`, etc. Read `BaseSDTrainProcess` to understand the training
lifecycle.

### Model support

Per-model logic lives across `toolkit/` (loaders, LoRA/quant handling in
`lora_special.py`, `lycoris_special.py`, `dequantize.py`, `memory_management/`)
and `extensions_built_in/diffusion_models`. The config selects a model by
name/path; adding a new model family means wiring its loader + the diffusers
pipeline, not adding a job type.

### The UI is a separate Next.js app that shells out to `run.py`

`ui/` is a standalone Next.js 15 + Prisma/SQLite (`aitk_db.db`) app on port
**8675**, independent of the Python package:

- `ui/cron/worker.ts` is a background worker; `ui/cron/actions/startJob.ts`
  **spawns `run.py` as a subprocess**, resolving the interpreter via
  `ui/cron/pythonPath.ts` → prefers `<repo>/.venv/bin/python` (the uv venv).
  So the UI automatically uses the uv-managed env — no PATH wiring needed.
- The UI writes a job config and launches it; training runs are child
  processes, not in-process. The UI need not stay running for a job to finish.
- Auth: `AI_TOOLKIT_AUTH` env var (put it in `.env`, loaded by the service).
- `npm run start` assumes a prior `npm run build`; the systemd unit runs
  `start`, so rebuild with `just ui-build` after UI changes, then `just restart`.

### Deployment

`deploy/aitoolkit.service` runs the UI on :8675 (parallel to a co-hosted
ComfyUI on :8188). See `deploy/README.md` for setup, auth, and the GPU
coexistence caveat (both services share one GPU; the unit omits ComfyUI's
`nvidia_uvm` modprobe pre-step so it won't disrupt a running ComfyUI).

## Datasets & configs

- Training data is a folder of images + same-named `.txt` caption files (jpg,
  jpeg, png). `[trigger]` in a caption is replaced by the config's
  `trigger_word`. Images are auto-resized and bucketed — no manual cropping.
- Start from `config/examples/` (e.g. `train_lora_flux_24gb.yaml`), copy into
  `config/`, and edit. `config/` and `output/` are runtime dirs (gitignored).
