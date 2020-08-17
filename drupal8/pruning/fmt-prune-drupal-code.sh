#!/bin/bash

# fmt-prune-drupal-code.sh
#
# Part of freelancers-mini-tools v0.1
#
# Removes directories known to not be used in production.
#
# Removes:
# - Core core/tests
# - Core module's tests/ subdirs
# - Disabled core and contrib modules
# - Disabled core themes
# - Demo Umami profile
#
# Part of freelancer-mini-tools v0.1
#
# Usage:
# /path/to/fmt-prune-drupal-code.sh
#
# Assuming:
# - This script is invoked from the directory where ./src/web/core/composer.json
#   resolves.
#
# To compare before/after, you can run:
#
# find . -printf "%h\n" | cut -d/ -f-2 | sort | uniq -c | sort -rn
#
# To get a count of the inodes for current dir + subdirs.

set -x

function prune_extensions() {
  _EXTENSION_LIST="$1"
  _BASE_DIR=$2
  if [ ! -z "$_EXTENSION_LIST" ]; then
    _DIRS_TO_PRUNE=$(extension_dirs "$_EXTENSION_LIST" $_BASE_DIR)
    prune_dirs "$_DIRS_TO_PRUNE"
  fi
}

function prune_dirs() {
  [ ! -z "$1" ] && \
    # Sort reverse to prevent notices about missing dirs; nested dirs must be
    # removed first.
    REV_SORTED_DIRS=$(echo -e "$1" | sort -r) && \
    chmod +w -R $REV_SORTED_DIRS && \
    rm -r $REV_SORTED_DIRS
}

function extension_dirs() {
  _EXTENSION_LIST="$1"
  _BASE_DIR=$2

   _EXTENSIONS_INFO_YMLS=$(sed 's/$/.info.yml/' <(echo "$_EXTENSION_LIST"))
   # grep finds the full-path for the passed .info.yml files, dirname resolves
   # their parent dir
   _ALL_INFO_YMLS=$(find $_BASE_DIR -name '*.info.yml')
   _FOUND_DIRS=$(dirname $(grep -F -f <(echo "$_EXTENSIONS_INFO_YMLS") <(echo "$_ALL_INFO_YMLS")))

   echo "$_FOUND_DIRS"
}

function find_unused() {
  _CORE_EXTENSION_YML=$1
  _BASE_DIR=$2

  _INSTALLED_LIST=$(cat $_CORE_EXTENSION_YML | grep -E ": [0-9]+" | cut -d: -f-1 | sed -e 's/^[[:space:]]*//')
  _ALL_INFO_YMLS=$(find $_BASE_DIR -name '*.info.yml')
  _ALL_EXTENSIONS=$(echo "$_ALL_INFO_YMLS" | xargs -I{} basename {} \; | cut -d. -f-1)
  _UNUSED_EXTENSIONS=$(grep -vxF -f <(echo "$_INSTALLED_LIST") <(echo "$_ALL_EXTENSIONS") | sort)

  echo "$_UNUSED_EXTENSIONS"
}

# Start by pruning tests
[ -d src/web/core/tests ] && \
  prune_dirs src/web/core/tests

CORE_MODULES_TESTS_DIRS=$(find src/web/core/modules -type d -name tests)
prune_dirs "$CORE_MODULES_TESTS_DIRS"

SYMFONY_TESTS_DIRS=$(find src/vendor/symfony -type d -name Tests)
prune_dirs "$SYMFONY_TESTS_DIRS"

# Prune Umami demo profile.
[ -d src/web/core/profiles/demo_umami ] && \
  prune_dirs src/web/core/profiles/demo_umami

# Find exported core.extension.yml which is *not* from core itself.
CORE_EXTENSION_YML=$(find . -name core.extension.yml | grep -v "core/config/install")
[ -z "$CORE_EXTENSION_YML" ] && \
  echo "Can not find core.extension.yml; did you export the configuration?" && \
  exit 1

UNUSED_CORE_MODULES=$(find_unused $CORE_EXTENSION_YML src/web/core/modules)
prune_extensions "$UNUSED_CORE_MODULES" src/web/core/modules

UNUSED_CORE_THEMES=$(find_unused $CORE_EXTENSION_YML src/web/core/themes)
UNUSED_CORE_THEMES=$(grep -vF "twig" <(echo "$UNUSED_CORE_THEMES"))
prune_extensions "$UNUSED_CORE_THEMES" src/web/core/themes

UNUSED_CONTRIB_MODULES=$(find_unused $CORE_EXTENSION_YML src/web/modules)
prune_extensions "$UNUSED_CONTRIB_MODULES" src/web/modules
