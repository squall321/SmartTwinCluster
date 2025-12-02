#!/usr/bin/env bash
set -euo pipefail

WORKDIR="./"
echo "=== KooCAEWeb Dev Setup Script ==="
cd "$WORKDIR"

echo "[0/7] Node/npm sanity check"
# Recommend Node 18/20/22 LTS. Show what we have.
node -v || true
npm -v || true






echo "[1/7] Clean node_modules & lockfile"
rm -rf node_modules package-lock.json

echo "[2/7] (optional) Pin a good npm version (works well with optional deps)"
# If this errors due to permissions, skip it; not fatal.
npm i -g npm@10 || true
npm --version || true

echo "[3/7] Clean npm cache"
npm cache clean --force

echo "[4/7] Install (force include optional deps)"
# --include=optional guards against the omit bug
npm install --include=optional

# If the rollup native binary still didn?t land (rare), install it explicitly
echo "[5/7] Ensure Rollup native binary for this platform"
ARCH="$(uname -m)"
LIBC="gnu"
PKG=""
if [[ "$ARCH" == "x86_64" ]]; then
  PKG="@rollup/rollup-linux-x64-$LIBC"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
  PKG="@rollup/rollup-linux-arm64-$LIBC"
fi
if [[ -n "${PKG}" ]]; then
  # Try installing the platform package (won't hurt if already installed)
  npm i -D "$PKG" || true
fi

echo "[6/7] Verify rollup resolution"
node -e "require('rollup'); console.log('rollup ok')" || {
  echo "Rollup native binary still missing. Trying once more with reinstall?"
  rm -rf node_modules package-lock.json
  npm cache clean --force
  npm install --include=optional --force
  node -e "require('rollup'); console.log('rollup ok')"
}

echo "[7/7] Done! Start dev server with:"
echo "       npm run dev -- --host 0.0.0.0 --port 5173"
WORKDIR="./"
echo "=== KooCAEWeb Dev Setup Script ==="
cd "$WORKDIR"
