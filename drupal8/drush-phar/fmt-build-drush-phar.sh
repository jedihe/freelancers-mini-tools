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
  curl -LSs https://box-project.github.io/box2/installer.php | php
  chmod +x $BOX_PHAR
else
  php $BOX_PHAR update
fi

# Build steps adapted from https://github.com/box-project/box2/wiki/Drush
DRUSH_VERSION="${1:-9.7.2}"
DRUSH_BUILD_DIR="$WORK_DIR/build-$DRUSH_VERSION"
mkdir -p $DRUSH_BUILD_DIR
cd $DRUSH_BUILD_DIR

CORE_COMPOSER_JSON=$(readlink -f $(find $START_DIR -name composer.json | sort | grep "core/composer.json" -))
CORE_REQUIRED_PACKAGES=$(cat $CORE_COMPOSER_JSON | \
  jq -r '.["require"] | to_entries | map (.key + ":" + .value) | join("\n")' - | \
  grep -v -E "(ext-|php)" | \
  sort)
CORE_REQUIRED_PACKAGES_NAMES=$(echo "$CORE_REQUIRED_PACKAGES" | cut -d: -f-1)

# Try to ensure compatibility with the site by performing the build with the
# same constraints as the site's Drupal core.
ls composer.lock || composer require drush/drush:$DRUSH_VERSION $CORE_REQUIRED_PACKAGES --prefer-dist

# Remove build-only dependencies, which would only bloat the final .phar.
BUILD_ONLY_DEPENDENCIES=""
for DEP in $CORE_REQUIRED_PACKAGES_NAMES; do
  IS_REQUIRED_BY_DRUSH=$(composer why --recursive $DEP | grep "^drush/drush" -)
  if [[ "$IS_REQUIRED_BY_DRUSH" == "" ]]; then
    BUILD_ONLY_DEPENDENCIES="$BUILD_ONLY_DEPENDENCIES $DEP"
  fi
done
composer remove $BUILD_ONLY_DEPENDENCIES

BOX_JSON=$(cat <<-SNIPPET
{
    "alias": "drush-$DRUSH_VERSION.phar",
    "chmod": "0755",
    "directories": ["vendor"],
    "finder": [
        {
            "name": "*.php",
            "exclude": ["Tests"],
            "in": "vendor"
        }
    ],
    "compactors": [
        "Herrera\\\\Box\\\\Compactor\\\\Json",
        "Herrera\\\\Box\\\\Compactor\\\\Php"
    ],
    "main": "vendor/drush/drush/drush.php",
    "output": "drush-$DRUSH_VERSION.phar",
    "stub": true
}
SNIPPET
)
echo "$BOX_JSON" > $DRUSH_BUILD_DIR/box.json
time php -d phar.readonly="Off" ../box.phar build

echo "Built phar for Drush $DRUSH_VERSION at:"
echo "$DRUSH_BUILD_DIR/drush-$DRUSH_VERSION.phar"
