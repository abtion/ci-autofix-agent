# CI Autofix Agent Conventions

Applies to every commit and comment made by the CI autofix agent.

## Commit prefix (Conventional Commits)

| Trigger | Prefix |
|---|---|
| Failing CI on default branch | `fix(ci):` |
| Failing CI on a PR — linter (rubocop / eslint / stylelint / prettier / erb-lint) | `fix(lint):` |
| Failing CI on a PR — test suite (rspec / jest / vitest) | `fix(test):` |
| Failing CI on a PR — type-checker (tsc) | `fix(types):` |
| Failing CI on a PR — i18n tasks | `fix(i18n):` |
| Failing CI on a PR — schema drift | `fix(db):` |
| Failing CI on a PR — security scanner (brakeman) | `fix(security):` |
| Dependabot PR with broken CI | `chore(deps):` |
| Security advisory fix | `security(deps):` |
| Flaky test stabilisation | `chore(test):` |

Add project-specific rows here as needed.

## Final response format

The workflow updates a single PR comment per run with the agent's outcome.
To make that comment useful, conclude your final response with a one-line
summary of what was broken and what was fixed. Example:

```
Updated TaskList component to handle the new react-router-dom v7 loader signature after the dependency bump.
```

Do NOT post a PR comment yourself, do NOT include cost/turns/run-link
(the workflow appends those), and do NOT include "Verified: …" — the
workflow already verifies via the failing CI re-run.

## What the agent must NOT do

- Post PR comments (the workflow owns the status comment)
- Modify `.github/workflows/*` or `.github/actions/*`
- Edit lockfiles directly (`Gemfile.lock`, `package-lock.json`, `pnpm-lock.yaml`) —
  change the manifest and let the package manager regenerate them
- Downgrade or revert a Dependabot update — fix the calling code instead
- Touch `.env`, `.env.*`, or any credential file
- Force-push or rewrite history
- Auto-merge or approve any PR
- Create new branches
- Open PRs
