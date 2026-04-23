#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/home/yusuf/projects/monad"
BRANCH="main"
SKIP_PULL="false"

if [[ "${1:-}" == "--skip-pull" ]]; then
  SKIP_PULL="true"
fi

cd "$PROJECT_DIR"

exec 9>/tmp/monad-production-deploy.lock
if ! flock -n 9; then
  echo "Another Monad deploy is already running."
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_cmd git
require_cmd npm
require_cmd pm2

git update-index -q --refresh
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Deploy aborted: tracked local changes exist in $PROJECT_DIR."
  echo "Commit, stash, or revert them before deploying."
  git status --short
  exit 1
fi

if [[ "$SKIP_PULL" != "true" ]]; then
  git fetch origin "$BRANCH"
  git checkout "$BRANCH"
  git pull --ff-only origin "$BRANCH"
fi

echo "Installing backend dependencies..."
npm ci --prefix backend

echo "Running backend tests..."
npm test --prefix backend

echo "Installing frontend dependencies..."
npm ci --prefix frontend

echo "Building frontend..."
npm run build --prefix frontend

echo "Reloading PM2 processes..."
pm2 startOrReload ecosystem.config.cjs --update-env
pm2 save

echo "Monad deploy completed."
