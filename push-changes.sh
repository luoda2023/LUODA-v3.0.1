#!/bin/bash
# Script to push changes and trigger CI builds
# Run this from the repo root: cd LUODA-v3.0.1 && bash push-changes.sh
# Requires: git with access to github.com

set -e

REPO="luoda2023/LUODA-v3.0.1"

echo "=== Current branch: v3.0.1 ==="
echo "The following commits will be pushed:"
git log origin/v3.0.1..HEAD --oneline

echo ""
echo "=== Pushing v3.0.1 (will auto-trigger CI) ==="
echo "CI will run: build-exe.yml + build-msi.yml + build-apk.yml + build-deb.yml + build-web.yml"
echo ""

read -p "Push now? (Y/n): " push_choice
if [ "$push_choice" = "n" ] || [ "$push_choice" = "N" ]; then
  echo "Push cancelled."
  exit 0
fi

git push origin v3.0.1 2>&1

echo ""
echo "=== Optionally merge v3.0.1 into master for stable release? ==="
read -p "Merge v3.0.1 into master? (y/N): " master_choice
if [ "$master_choice" = "y" ] || [ "$master_choice" = "Y" ]; then
  git checkout master
  git pull --ff-only origin master 2>/dev/null || true
  git merge v3.0.1 --no-ff -m "Merge v3.0.1 into master for stable release"
  git push origin master
  git checkout v3.0.1
fi

echo ""
echo "=== Done ==="
echo "Check CI status at: https://github.com/$REPO/actions"
