#!/bin/bash

# fmt-tag-build.sh
#
# Part of freelancers-mini-tools v0.1
#
# Simplifies tagging of builds, by generating simple tags (ENV.ID), with ID
# +1ed each time.
#
# Usage:
#
# /path/to/tag-build.sh target_env
#
# If not provided, 'target_env' defaults to 'dev'.
#
# Version: 0.1.1
#
# ==============================================================================
#
# TODO:
#
# - Restrict tagging to specific target_envs.

#set -x

TARGET_ENV=${1:-dev}
CUR_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Only allow tagging on master or main branch.
[ "$CUR_BRANCH" !~ "master|main"  ] &&
  echo "ERROR: tagging is only allowed on branches: master, main. You should merge your current work first, then try again." &&
  exit 1

LAST_TAG=$(git tag --list "$TARGET_ENV.*" | sort --version-sort | tail -n1)
CUR_COMMIT=$(git rev-parse HEAD)
if [ "$LAST_TAG" == "" ]; then
  # First time tagging for that $TARGET_ENV.
  NEW_TAG="$TARGET_ENV.1"
else
  # git rev-parse is not reliable for tags, see
  # https://stackoverflow.com/a/1862542/6072846
  LAST_TAG_COMMIT=$(git rev-list -1 $LAST_TAG)
  [ "$LAST_TAG_COMMIT" == "$CUR_COMMIT" ] &&
    echo "Error: The current commit is already tagged for the '$TARGET_ENV' environment." &&
    exit 1

  LAST_TAG_COUNTER=${LAST_TAG#*.}
  NEW_TAG_COUNTER=$((LAST_TAG_COUNTER+1))
  NEW_TAG="$TARGET_ENV.$NEW_TAG_COUNTER"
fi

git tag -a "$NEW_TAG" -m "Tagging version $NEW_TAG"

echo "Tagged new version $NEW_TAG, on commit $CUR_COMMIT."
echo "To discard, run (remove leading #):"
echo "# git tag -d $NEW_TAG"
