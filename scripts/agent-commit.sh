#!/usr/bin/env bash
# Create a signed commit on the current branch via the GitHub REST API.
#
# When authenticated with a GitHub App Installation Token (which `gh` picks
# up from $GITHUB_TOKEN in the workflow), GitHub signs the resulting commit
# with its own GPG key. The commit then displays the "Verified" badge on
# github.com and the App identity stays as the commit author.
#
# Usage:   bash .github/scripts/agent-commit.sh "<commit message>"
# Requires: git, gh (authenticated), jq, base64. $GITHUB_REPOSITORY must be
#           set (GitHub Actions provides this automatically).

set -euo pipefail

MSG="${1:?usage: agent-commit.sh <commit message>}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"

REPO="$GITHUB_REPOSITORY"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
HEAD_SHA="$(git rev-parse HEAD)"
BASE_TREE="$(git rev-parse "$HEAD_SHA^{tree}")"

if [ "$BRANCH" = "HEAD" ]; then
  echo "agent-commit: detached HEAD; cannot determine branch." >&2
  exit 1
fi

# Stage every working-tree change so the index represents the full intent.
git add -A

if git diff --cached --quiet; then
  echo "agent-commit: no staged changes; nothing to commit." >&2
  exit 1
fi

# Returns the index mode (e.g. 100644, 100755, 120000) for a staged path.
mode_of() {
  git ls-files --stage -- "$1" | awk '{print $1; exit}'
}

# Upload a blob for $1 and echo the returned SHA.
make_blob() {
  local path="$1" content mode
  mode="$(mode_of "$path")"
  if [ "$mode" = "120000" ]; then
    content="$(readlink -- "$path" | base64 | tr -d '\n')"
  else
    content="$(base64 < "$path" | tr -d '\n')"
  fi
  jq -n --arg c "$content" '{content: $c, encoding: "base64"}' \
    | gh api -X POST "repos/$REPO/git/blobs" --input - --jq .sha
}

# Build the tree-entry array incrementally in a temp file using jq.
entries_file="$(mktemp)"
trap 'rm -f "$entries_file" "$entries_file.tmp"' EXIT
echo '[]' > "$entries_file"

append_upsert() {
  local path="$1" mode sha
  mode="$(mode_of "$path")"
  sha="$(make_blob "$path")"
  jq --arg p "$path" --arg m "$mode" --arg s "$sha" \
     '. + [{path: $p, mode: $m, type: "blob", sha: $s}]' \
     "$entries_file" > "$entries_file.tmp"
  mv "$entries_file.tmp" "$entries_file"
}

append_delete() {
  local path="$1"
  jq --arg p "$path" \
     '. + [{path: $p, mode: "100644", type: "blob", sha: null}]' \
     "$entries_file" > "$entries_file.tmp"
  mv "$entries_file.tmp" "$entries_file"
}

# Iterate over staged changes. `--name-status` is tab-separated:
#   <status>\t<path>          (A, M, T, D)
#   <status>\t<old>\t<new>    (R*, C*)
while IFS=$'\t' read -r status p1 p2; do
  case "$status" in
    A|M|T)
      # Skip gitlinks (mode 160000) — submodule references, not file content.
      [ "$(mode_of "$p1")" = "160000" ] && continue
      append_upsert "$p1"
      ;;
    D)      append_delete "$p1" ;;
    R*|C*)
      append_delete "$p1"
      [ "$(mode_of "$p2")" = "160000" ] && continue
      append_upsert "$p2"
      ;;
    *)      echo "agent-commit: unsupported diff status: $status $p1" >&2; exit 1 ;;
  esac
done < <(git diff --cached --name-status)

# Create the tree.
NEW_TREE="$(jq --arg base "$BASE_TREE" --slurpfile entries "$entries_file" \
              -n '{base_tree: $base, tree: $entries[0]}' \
            | gh api -X POST "repos/$REPO/git/trees" --input - --jq .sha)"

# Create the commit. Author and committer are populated server-side from
# the App Installation Token; GitHub signs the commit with its own key.
NEW_COMMIT="$(jq -n --arg msg "$MSG" --arg tree "$NEW_TREE" --arg parent "$HEAD_SHA" \
                '{message: $msg, tree: $tree, parents: [$parent]}' \
              | gh api -X POST "repos/$REPO/git/commits" --input - --jq .sha)"

# Update the branch ref. force=false: a concurrent commit on the branch
# will surface as a 422 and stop us — we never overwrite.
if ! jq -n --arg sha "$NEW_COMMIT" '{sha: $sha, force: false}' \
     | gh api -X PATCH "repos/$REPO/git/refs/heads/$BRANCH" --input - >/dev/null; then
  echo "agent-commit: ref update failed (likely a concurrent commit on $BRANCH)." >&2
  exit 1
fi

# Sync the local clone so subsequent agent work sees the real branch state.
git fetch --quiet origin "$BRANCH"
git reset --hard --quiet "origin/$BRANCH"

echo "Created verified commit $NEW_COMMIT on $BRANCH."
