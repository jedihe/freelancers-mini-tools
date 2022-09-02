#!/bin/bash

# Inspired by some comments at https://github.com/drush-ops/drush/issues/3331

# fmt-build-drush-phar.sh
#
# Part of freelancers-mini-tools v0.1
#
# Requirements:
# - composer
# - jq
#
# Usage:
# /path/to/fmt-build-drush-phar.sh DRUSH-VERSION
#
# Assuming:
# - The script is called from a parent dir of the drupal-root.
# - DRUSH-VERSION is compatible with the Drupal core version.
#
# Version: 0.1.2
#
# TODO:
# - Analyze if it's feasible to rm directories from vendor for which the site's
#   vendor dir should already have a compatible version. E.g. twig/twig.
# - Think about potential pruning/cleanup techniques that should help in
#   reducing the .phar filesize.

set -x

START_DIR=$(pwd)

WORK_DIR="/tmp/drush-phar"
BOX_PHAR="$WORK_DIR/box.phar"
mkdir -p $WORK_DIR
cd $WORK_DIR

# For simplicity, we're using the suggested install method for box2. If
# preferred to do a direct download, check the releases page in github:
# https://github.com/box-project/box2/releases
if [ ! -e $BOX_PHAR ]; then
  curl -LSs https://github.com/box-project/box/releases/download/3.16.0/box.phar -o box.phar
  chmod +x $BOX_PHAR
else
  php $BOX_PHAR update
fi

# Build steps adapted from https://github.com/box-project/box2/wiki/Drush
DRUSH_VERSION="${1:-9.7.2}"
DRUSH_BUILD_DIR="$WORK_DIR/build-$DRUSH_VERSION"
mkdir -p $DRUSH_BUILD_DIR
cd $DRUSH_BUILD_DIR

SITE_COMPOSER_JSON=$(readlink -f $(find $START_DIR -name composer.json | sort | head -n1 | grep "composer.json" -))
SITE_REQUIRED_PACKAGES=$(cat $SITE_COMPOSER_JSON | \
  jq -r '.["require"] | to_entries | map (.key + ":" + .value) | join("\n")' - | \
  `# Remove spaces to support constraints like ^1.0 || ^2.0. WARNING: this comment requires backticks!` \
  tr -d " " | \
  grep -v -E "(ext-|php)" | \
  sort)
SITE_REQUIRED_PACKAGES_NAMES=$(echo "$SITE_REQUIRED_PACKAGES" | cut -d: -f-1)

# Try to ensure compatibility with the site by performing the build with the
# same constraints as the site's composer.json.
ls composer.lock || \
  (composer init --name=fmt/drush-phar-build -n && \
  composer config repositories.drupal composer https://packages.drupal.org/8 && \
  composer require drush/drush:$DRUSH_VERSION $SITE_REQUIRED_PACKAGES --prefer-dist) || \
  { echo "ERR: composer require failed, check that drush $DRUSH_VERSION is compatible with $SITE_COMPOSER_JSON."; exit 1; }

# Remove build-only dependencies, which would only bloat the final .phar.
BUILD_ONLY_DEPENDENCIES=""
for DEP in $SITE_REQUIRED_PACKAGES_NAMES; do
  IS_REQUIRED_BY_DRUSH=$(composer why --recursive $DEP | grep "^drush/drush" -)
  if [[ "$IS_REQUIRED_BY_DRUSH" == "" ]]; then
    BUILD_ONLY_DEPENDENCIES="$BUILD_ONLY_DEPENDENCIES $DEP"
  fi
done
composer remove $BUILD_ONLY_DEPENDENCIES

DRUSH_FINAL_VERSION=$(cat $DRUSH_BUILD_DIR/composer.lock | jq -r '.packages | map(select(.name == "drush/drush")) | .[].version')

BOX_JSON=$(cat <<-SNIPPET
{
    "alias": "drush-$DRUSH_FINAL_VERSION.phar",
    "compactors": [
        "KevinGH\\\\Box\\\\Compactor\\\\Json"
    ],
    "main": "vendor/drush/drush/drush.php",
    "output": "drush-$DRUSH_FINAL_VERSION.phar"
}
SNIPPET
)
echo "$BOX_JSON" > $DRUSH_BUILD_DIR/box.json

time php -d phar.readonly="Off" ../box.phar build

echo "Built phar for Drush $DRUSH_VERSION at:"
echo "$DRUSH_BUILD_DIR/drush-$DRUSH_FINAL_VERSION.phar"
