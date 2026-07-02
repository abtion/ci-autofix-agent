# ci-autofix-agent

A reusable GitHub Action that puts Claude Code to work on your pull requests. It responds to two kinds of events:

- **CI failed** — the agent reads the failed logs, reproduces the failure, and applies the minimum fix.
- **A reviewer left feedback** — the agent reads the review and addresses the actionable comments.

In both cases the agent verifies its changes locally and commits a GitHub-signed (**Verified**) commit straight back to the PR branch — never a new branch, never a force-push.

## Triggers

The workflow (`agent-fix-ci.yml`) listens for two events, and the trigger decides what context the agent receives and what counts as "done".

### CI failure — `workflow_run`

1. Your CI workflow fails on a PR.
2. The agent triggers via `workflow_run`.
3. It downloads the failed job logs, diagnoses the root cause, reproduces the failure locally, and applies the **minimum** fix.

Only failures whose job names match `FIXABLE_CI_JOBS` are attempted — everything else is skipped to save credits (see [precheck](#precheck)).

### PR review — `pull_request_review`

1. A reviewer submits a review that **requests changes** or **comments** — approvals are ignored.
2. The agent triggers via `pull_request_review`.
3. It reads the PR description, general comments, review summary bodies (where Copilot/Gemini often leave their analysis), and unresolved inline review threads.
4. It addresses the actionable code feedback with the minimum change, then posts a **"Comments considered"** summary that lists every comment as *addressed* or *skipped*, each with a one-line reason. Questions, off-topic, and out-of-scope comments are skipped.

By default only **bot** reviews (Copilot, Gemini, etc.) trigger the agent; set `REVIEW_TRIGGER_ACTORS` to `humans` or `all` to change that. A bot reviewer must additionally be listed in `ALLOWED_BOTS` — the two filters compose.

## What happens on every run

Whichever event fires, the rest of the pipeline is shared:

1. A **precheck** gates the run: the kill switch is off, the [retry limit](#precheck) hasn't been reached, and — for CI failures — a fixable job actually failed.
2. **run-agent** generates a GitHub App token, resolves the PR, gathers the relevant context (failed logs for CI failures; the PR conversation whenever a PR is associated), and posts a status comment on the PR while it works.
3. Claude Code makes the change and **verifies** it by running the project's checks from `CLAUDE.md` — this happens on review triggers too, so an edit never regresses CI.
4. The commit is created through the GitHub API with the App token, so it lands as **Verified**. The status comment is then updated with the outcome — success, or the reason the agent couldn't act — along with cost and turn count.

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

The template already listens for both triggers (`workflow_run` and `pull_request_review`); copy it into `.github/workflows/agent-fix-ci.yml` in your repository and fill in the env vars at the top:
- `AGENT_BOT_NAME` — pre-filled as `claude-autofixing-agent`, change only if using a different App
- `FIXABLE_CI_JOBS` — ERE regex of job names the agent should attempt to fix (CI-failure trigger only)
- `ALLOWED_BOTS` — accounts allowed to trigger the agent, matched against the workflow actor `github.actor` (default: `dependabot[bot]`; `*` allows all). The actor isn't always the review author: GitHub's built-in Copilot review runs as actor `Copilot`, so add `Copilot` (not `copilot-pull-request-reviewer[bot]`) to act on it
- `REVIEW_TRIGGER_ACTORS` — on PR reviews, which reviewer types trigger the agent: `bots` (default), `humans`, or `all`. Bot reviewers must also be in `ALLOWED_BOTS`
- `MODEL` — Claude model to use (default: `claude-sonnet-4-6`)
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
| `workflow_run_id` | No | ID of the failed workflow run. Leave empty for `pull_request_review` triggers; the fixable-jobs check is then skipped. |
| `review_actor_type` | No | Review author's account type (`github.event.review.user.type`). Empty for non-review triggers; the review-actor filter is then skipped. |
| `allowed_review_actors` | No | For `pull_request_review`: which reviewer types may trigger — `bots` (default), `humans`, or `all`. |
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
