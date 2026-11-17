#!/bin/zsh
# Moves the josue branch onto upstream's newest release tag (or one you name),
# waits for GitHub Actions to test it and build the image, then deploys it on
# menddell: backup, pull, migrate, restart, health check.
#
#   Local/update.sh                     newest upstream release tag
#   Local/update.sh v2026.11.20-alpha   a specific tag
#   Local/update.sh --deploy            deploy the current josue image again
#
# It stops and explains instead of forcing on a rebase conflict, a failed
# build or a failed health check.

set -euo pipefail

script_path="${0:A}"

HOST=${SURE_HOST:-menddell}
REMOTE_DIR=sure
FORK=JosueM1109/sure
IMAGE=ghcr.io/josuem1109/sure
HEALTH_URL=http://192.168.1.86:4440/up

# The whole script is one function, so zsh has parsed all of it before the
# rebase rewrites the working tree (this file included).
main() {
  local repo="${script_path:h:h}"
  cd "$repo"

  if [[ "${1:-}" != "--deploy" ]]; then
    move_branch "${1:-}"
    wait_for_image
  fi

  local base="$(git describe --tags --abbrev=0 --match 'v2*' HEAD)"
  deploy "${base}-josue"
}

move_branch() {
  if [[ "$(git branch --show-current)" != "josue" ]]; then
    print -u2 "Switch to the josue branch first (git switch josue)."
    exit 1
  fi
  if ! git diff --quiet || ! git diff --cached --quiet; then
    print -u2 "You have uncommitted changes. Commit them (or git stash) and rerun."
    exit 1
  fi

  print "Fetching upstream releases..."
  git fetch upstream --tags --prune --quiet
  local target="${1:-$(git tag --list 'v2*' --sort=-creatordate | head -n 1)}"
  git rev-parse --verify --quiet "${target}^{commit}" >/dev/null \
    || { print -u2 "Unknown tag: $target"; exit 1; }

  if git merge-base --is-ancestor "$target" HEAD; then
    print "Already on $target. Use --deploy to redeploy."
    exit 0
  fi

  local old_head="$(git rev-parse HEAD)"
  print "Moving josue onto $target..."
  if ! git rebase "$target"; then
    print -u2 ""
    print -u2 "One of the fork's commits conflicts with upstream's changes."
    print -u2 "  1. Fix the files git lists (git status), then: git add <files>"
    print -u2 "  2. git rebase --continue   (repeat until it finishes)"
    print -u2 "  3. git push --force-with-lease origin josue, then Local/update.sh --deploy"
    print -u2 "To give up and go back: git rebase --abort"
    print -u2 "Your branch before the update: $old_head"
    exit 1
  fi

  # Upstream's workflows must never publish from the fork. GitHub only lists a
  # workflow once it has seen it, so disable any new ones on every update.
  gh api "repos/$FORK/actions/workflows" --paginate \
    --jq '.workflows[] | select(.state == "active" and .path != ".github/workflows/josue-image.yml") | .id' \
    | while read -r id; do gh workflow disable "$id" --repo "$FORK" >/dev/null && print "Disabled upstream workflow $id"; done

  print "Pushing josue (GitHub Actions runs the Plaid tests, then builds the image)..."
  git push --quiet --force-with-lease origin josue
}

wait_for_image() {
  local sha="$(git rev-parse HEAD)" run_id=""
  print "Waiting for the Josue image run for ${sha:0:9}..."
  for _ in {1..30}; do
    run_id="$(gh run list --repo "$FORK" --workflow josue-image.yml --branch josue --commit "$sha" \
      --json databaseId --jq '.[0].databaseId // empty')"
    [[ -n "$run_id" ]] && break
    sleep 10
  done
  [[ -n "$run_id" ]] || { print -u2 "No workflow run showed up for $sha."; exit 1; }

  if ! gh run watch "$run_id" --repo "$FORK" --exit-status --interval 30 >/dev/null; then
    print -u2 "The tests or the image build failed: gh run view $run_id --repo $FORK --log-failed"
    print -u2 "menddell still runs the previous image."
    exit 1
  fi
  print "Image built."
}

deploy() {
  local tag="$1"
  print "Deploying $IMAGE:$tag on $HOST..."
  scp -q Local/menddell-compose.yml "$HOST:$REMOTE_DIR/compose.yml"
  scp -q Local/backup.sh "$HOST:$REMOTE_DIR/backup.sh"
  ssh "$HOST" "TAG='$tag' bash -s" <<'REMOTE'
set -euo pipefail
cd ~/sure
previous=$(grep -E '^SURE_IMAGE_TAG=' .env | cut -d= -f2-)
echo "Backing up first (current image: ${previous:-unknown})..."
./backup.sh
docker pull --quiet "ghcr.io/josuem1109/sure:$TAG" >/dev/null
sed -i "s/^SURE_IMAGE_TAG=.*/SURE_IMAGE_TAG=$TAG/" .env
# web runs db:prepare (migrations) when it starts.
docker compose up -d --remove-orphans web worker
for i in $(seq 1 36); do
  if curl -fsS -m 5 -o /dev/null http://127.0.0.1:4440/up; then
    echo "Healthy on $TAG."
    docker image prune -f --filter "label=org.opencontainers.image.source=https://github.com/JosueM1109/sure" >/dev/null
    exit 0
  fi
  sleep 5
done
echo "Not healthy after 3 minutes. Logs: docker compose logs --tail 100 web" >&2
echo "Roll back: set SURE_IMAGE_TAG=$previous in ~/sure/.env, restore the backup just taken" >&2
echo "(docker compose stop web worker && docker compose run --rm backup restore latest), then docker compose up -d." >&2
exit 1
REMOTE
  curl -fsS -m 10 -o /dev/null "$HEALTH_URL" && print "Done: https://budget.mendhome.net"
}

main "$@"
