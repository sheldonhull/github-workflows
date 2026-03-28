# Proposal: Container-Based CI Bot as GitHub Actions Alternative

## Problem Statement

GitHub Actions runs every check on every push, leading to significant wasted
compute time. Even with path filters, concurrency controls, and duplicate
detection, there are inherent limitations:

- **Cold start overhead**: Every job spins up a fresh runner (~15-30s)
- **Tool installation**: Even with caching, aqua/trunk/go setup adds 30-60s per job
- **Sequential gating**: Path filter → gate → actual job still has pipeline latency
- **No persistent state**: Each run is stateless; no incremental analysis possible

## Proposed Architecture: Socket-Mode CI Bot

A long-running container that responds to GitHub webhooks in real-time,
maintaining a warm cache of tools and prior analysis results.

### Components

```
┌─────────────────────────────────────────────────┐
│  Container Group (ACI / Cloud Run / ECS)        │
│                                                  │
│  ┌──────────────┐  ┌────────────────────────┐   │
│  │ Webhook       │  │ Worker Pool            │   │
│  │ Receiver      │──│                        │   │
│  │ (socket mode) │  │ - Lint worker (trunk)  │   │
│  │               │  │ - Test worker (go)     │   │
│  │ GitHub App    │  │ - Security worker      │   │
│  └──────────────┘  │ - Release validator     │   │
│                     └────────────────────────┘   │
│                                                  │
│  ┌──────────────┐  ┌────────────────────────┐   │
│  │ Tool Cache    │  │ Analysis Cache         │   │
│  │ (volume)      │  │ (last-known-good,      │   │
│  │ aqua, trunk,  │  │  incremental diffs)    │   │
│  │ go toolchain  │  │                        │   │
│  └──────────────┘  └────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### How It Works

1. **GitHub App** receives push/PR webhooks via socket mode (no public endpoint needed)
2. **Webhook Receiver** evaluates changed files using the GitHub API diff
3. **Worker Pool** runs only relevant checks with pre-installed tools (zero cold start)
4. **Results** posted back as check runs / PR comments via the GitHub Checks API
5. **Analysis Cache** enables incremental linting (only re-lint changed files + their dependents)

### Performance Comparison

| Metric | GitHub Actions (current) | Container Bot (proposed) |
|--------|-------------------------|-------------------------|
| Cold start | 15-30s per job | 0s (warm container) |
| Tool setup | 30-60s (cached) | 0s (pre-installed) |
| Path detection | ~10s (checkout + filter) | ~1s (API diff, no checkout) |
| Lint (full) | 60-90s | 5-15s (incremental) |
| Go test (cached) | 30-60s | 10-20s (warm module cache) |
| Total preflight | 2-4 min | 10-30s |

### Implementation Options

#### Option A: Probot + Container Group (Recommended)

- **Runtime**: [Probot](https://probot.github.io/) framework for GitHub App
- **Hosting**: Azure Container Instances (ACI) or AWS Fargate
- **Socket mode**: Probot supports webhook delivery via smee.io proxy, or
  direct socket mode with a GitHub App configured for webhook forwarding
- **Cost**: ~$15-30/month for a single-instance container group

#### Option B: GitHub App + Azure Container Apps

- **Runtime**: Custom Go service using `google/go-github` library
- **Hosting**: Azure Container Apps (scale-to-zero with KEDA)
- **Advantage**: Native Go, matches your toolchain
- **Cost**: Near-zero when idle (scale-to-zero), ~$5-10/month active

#### Option C: Self-Hosted Runner with Persistent State

- **Runtime**: GitHub Actions self-hosted runner in a container
- **Hosting**: Any container platform you already manage
- **Advantage**: No code changes to workflows, just faster execution
- **Disadvantage**: Still bound by Actions runner lifecycle, less control over
  incremental analysis

### What to Move Off GitHub Actions

These checks benefit most from a container bot (stateful, fast feedback):

| Check | Why Move | Expected Speedup |
|-------|----------|------------------|
| **Trunk lint** | Incremental linting possible; warm tool cache | 4-6x |
| **Go vet/build** | Module cache persists; only rebuild changed packages | 3-5x |
| **Secret scanning** | Only scan new commits, not full history each time | 10x+ |
| **Preflight gating** | API-based diff vs checkout + path-filter | 10x+ |

These should **stay in GitHub Actions** (stateless, needs runner matrix):

| Check | Why Keep |
|-------|----------|
| **Release validation** | Infrequent, needs full checkout + tag context |
| **Docker build** | Needs Docker daemon, buildx, and GHA cache backend |
| **Dependency review** | GitHub-native integration with dependency graph |

### Migration Checklist

1. [ ] Create GitHub App with `checks:write`, `contents:read`, `pull_requests:read` permissions
2. [ ] Build container image with pre-installed: trunk, aqua, go toolchain, gitleaks
3. [ ] Implement webhook receiver (push, pull_request events)
4. [ ] Implement incremental lint: `trunk check --diff <base>...<head>`
5. [ ] Implement check run reporting via GitHub Checks API
6. [ ] Deploy container group with persistent volume for tool/module cache
7. [ ] Add health check endpoint and monitoring
8. [ ] Run in parallel with Actions for validation period
9. [ ] Disable redundant Actions workflows once bot is validated
10. [ ] Set up Renovate/Dependabot for container image dependencies

### Prerequisites You Already Have

Based on your existing infrastructure:
- Container group orchestration (ACI/ECS)
- Copilot environment prebuilds (devcontainer pattern)
- Renovate for dependency management
- Aqua for tool versioning

The container bot builds naturally on all of these.
