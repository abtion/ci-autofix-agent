# ci-autofix-agent

A reusable GitHub Action that automatically diagnoses and fixes CI failures using Claude Code. When CI fails on a pull request, the agent reads the logs, reproduces the failure locally, applies the minimum fix, and commits a GitHub-signed (Verified) commit back to the branch.

## How it works

1. Your CI workflow fails on a PR
2. `agent-fix-ci.yml` triggers via `workflow_run`
3. A **precheck** validates that the failure is fixable and the retry limit hasn't been reached
4. The **run-agent** action downloads the failed logs, invokes Claude Code, and posts the result as a PR comment
5. Commits are created via the GitHub API using a GitHub App token, so they show as **Verified**

## Prerequisites

### 1. GitHub App

The shared **claude-autofixing-agent** GitHub App is used across all Abtion projects. Install it on the target repository via the Abtion organisation settings and note the **App ID** (client ID) and **private key**.

The App requires these permissions:

| Permission | Access |
|---|---|
| Contents | Read & write |
| Pull requests | Read & write |
| Issues (comments) | Read & write |
| Actions | Read |
| Metadata | Read |

### 2. Add secrets to your repository

| Secret | Value |
|---|---|
| `AUTOFIX_APP_ID` | The GitHub App's client ID |
| `AUTOFIX_PRIVATE_KEY` | The GitHub App's private key (PEM) |
| `ANTHROPIC_API_KEY` | Your Anthropic API key |

### 3. Add project files

#### `agent-fix-ci.yml` — copy and fill in manually

Copy `templates/agent-fix-ci.yml` into `.github/workflows/agent-fix-ci.yml` in your repository and fill in the env vars at the top:
- `AGENT_BOT_NAME` — pre-filled as `claude-autofixing-agent`, change only if using a different App
- `FIXABLE_CI_JOBS` — ERE regex of job names the agent should attempt to fix
- `MAX_TURNS` — maximum Claude turns (default: 60)
- `EXTRA_ALLOWED_TOOLS` — extra `Bash(...)` patterns beyond the built-in defaults

Add your project-specific setup steps (language runtimes, database) in the marked section of the `fix` job.

#### `CLAUDE.md` and `AGENT_CONVENTIONS.md` — generate with Claude

Do **not** copy the templates for these files manually. Instead, use Claude Code to generate them for your specific project, using the templates as reference:

```bash
claude init
```

Then prompt Claude with something like:

```
Generate a CLAUDE.md and .github/AGENT_CONVENTIONS.md for this project,
following the structure and hard rules defined in the templates at:
https://raw.githubusercontent.com/abtion/ci-autofix-agent/v1/templates/CLAUDE.md
https://raw.githubusercontent.com/abtion/ci-autofix-agent/v1/templates/AGENT_CONVENTIONS.md

Inspect the actual codebase — stack, CI commands, linters, test runner,
lockfile conventions — and produce files that are accurate for this project,
not a generic copy of the templates.
```

Claude will inspect your codebase and produce files that accurately reflect your stack, CI commands, and project-specific rules. The templates define the required structure and the non-negotiable hard rules that every project must include — Claude fills in the project-specific parts.

### 4. Kill switch

Create `.github/CI_AUTOFIX_DISABLED` (empty file) in your repository to immediately disable the agent without touching the workflow.

## Inputs

### `precheck`

| Input | Required | Description |
|---|---|---|
| `bot_name` | Yes | GitHub App bot name (without `[bot]`) |
| `fixable_jobs` | Yes | ERE regex of fixable CI job names |
| `workflow_run_id` | Yes | ID of the failed workflow run |
| `github_token` | Yes | Token for `gh` CLI calls (`GITHUB_TOKEN` is sufficient) |
| `repository` | Yes | Repository in `owner/repo` format |

### `run-agent`

| Input | Required | Default | Description |
|---|---|---|---|
| `app_id` | Yes | — | GitHub App client ID |
| `app_private_key` | Yes | — | GitHub App private key PEM |
| `anthropic_api_key` | Yes | — | Anthropic API key |
| `bot_name` | Yes | — | GitHub App bot name (without `[bot]`) |
| `allowed_tools` | No | `""` | Extra comma-separated `Bash(...)` patterns |
| `max_turns` | No | `60` | Maximum Claude turns |
| `model` | No | `claude-sonnet-4-6` | Claude model to use |
| `allowed_bots` | No | `dependabot[bot]` | Comma-separated bot accounts (with `[bot]` suffix) whose events the agent may act on. Use `*` to allow all bots. |

## Versioning

Tag releases with `vN` (e.g. `v1`). Consuming repositories should pin to a major version tag:

```yaml
uses: abtion/ci-autofix-agent/precheck@v1
uses: abtion/ci-autofix-agent/run-agent@v1
```

To create the initial tag after pushing:

```bash
git tag v1
git push origin v1
```
