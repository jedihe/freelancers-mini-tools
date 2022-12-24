#!/bin/bash

# WARNING: do not remove!!!
set -ex

# Overrides: uncomment and set var value
#GROUP=

# OPTIONAL: enable and point to the right php version
#export PATH="/opt/cpanel/ea-php73/root/usr/bin:$PATH"
php -v

# Order of args:
# "$DEPLOY_DIR" "$BASE_DIR" "$DEPLOY_TAG" "$LINK_PATH"

DEPLOY_DIR=$1
BASE_DIR=$2
DEPLOY_TAG=$3
LINK_PATH=$4

BASE_DIR=$2
if [ ! -d $BASE_DIR ]; then
  echo "$BASE_DIR is not a directory, **ABORTING**"
  exit 1
fi

APP_ROOT=$1
if [ ! -f "$APP_ROOT/index.php" ]; then
  echo "$APP_ROOT/index.php not found, **ABORTING**."
  exit 1
fi

# Use common files dir
echo "Removing any existing $APP_ROOT/sites/default/files, in favor of linking to common files dir in $BASE_DIR"
#   First try to remove symlink
[ -h $APP_ROOT/sites/default/files ] && rm $APP_ROOT/sites/default/files
#   No symlink? then remove the dir recursively
[ -d $APP_ROOT/sites/default/files ] && rm -r $APP_ROOT/sites/default/files
#  Finally, link to the drupal-files dir
ln -s $BASE_DIR/app-files $APP_ROOT/sites/default/files

# Enable local settings
if [ -f $BASE_DIR/secrets/settings.local.php ]; then
  echo "Copy settings.local.php"
  ln -s $BASE_DIR/secrets/settings.local.php $APP_ROOT/sites/default/settings.local.php
  chmod 550 $APP_ROOT/sites/default/settings.local.php
fi

# Set proper ownership/permissions
# See https://www.drupal.org/node/244924#linux-servers
echo "Setting ownership/permissions"
OWNER=$(whoami)
cd $APP_ROOT
chown -R $OWNER:${GROUP:-$OWNER} .
find . -type d -exec chmod u=rwx,g=rx,o=rx '{}' \;
find . -type f -exec chmod u=rw,g=r,o=r '{}' \;

cd $APP_ROOT/sites
find . -type d -name files -exec chmod ug=rwx,o=rx '{}' \;
for d in ./*/files; do
 find $d -type d -exec chmod ug=rwx,o=rx '{}' \;
 find $d -type f -exec chmod ug=rw,o=r '{}' \;
done

# Set settings.php and settings.local.php as read-only
chmod ug=r,o= $APP_ROOT/sites/default/settings*.php
chmod ug=rx,o=rx $APP_ROOT/sites/default

# TODO: discover drush, automatically run updates + features-revert?
