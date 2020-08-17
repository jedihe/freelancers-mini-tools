#!/bin/bash

# WARNING: do not remove!!!
set -ex

# OPTIONAL: enable and point to the right php version
#alias php='/opt/cpanel/ea-php71/root/usr/bin/php'
#PHP='/opt/cpanel/ea-php71/root/usr/bin/php'
export PATH="/opt/cpanel/ea-php71/root/usr/bin:$PATH"
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

APP_ROOT="$DEPLOY_DIR/src/web"
if [ ! -f "$APP_ROOT/index.php" ]; then
  echo "$APP_ROOT/index.php not found, **ABORTING**."
  exit 1
fi

# Restore symlinks in vendor/bin
VENDOR_DIR="$DEPLOY_DIR/src/vendor"
chmod u+w $VENDOR_DIR/bin
for BIN_FILE in $VENDOR_DIR/bin/*; do
  # Check if the file contents make sense as a symlink (single line, resolves
  # to file from vendor/bin).
  if [ ! -h $BIN_FILE ] &&
     [ $(wc -l < $BIN_FILE) -eq 0 ] &&
     [ -f "$VENDOR_DIR/bin/$(cat $BIN_FILE)" ]; then

    TARGET=$(cat $BIN_FILE)
    rm $BIN_FILE
    ln -s $TARGET $BIN_FILE
    # Ensure the link target is executable.
    chmod ug+x "$VENDOR_DIR/bin/$TARGET"
  fi
done

# Make all files writable by the user (owner).
chmod u+w -R $APP_ROOT

# Enable local settings
if [ -f $BASE_DIR/secrets/settings.local.php ]; then
  echo "Copying settings.local.php"
  cp $BASE_DIR/secrets/settings.local.php $APP_ROOT/sites/default
  chmod 550 $APP_ROOT/sites/default/settings.local.php
fi

cd $DEPLOY_DIR

# Put the site in maintenance mode.
if [ -f $VENDOR_DIR/bin/drush ]; then
  php $VENDOR_DIR/bin/drush sset system.maintenance_mode TRUE -y
fi

# Set proper ownership/permissions
# See https://www.drupal.org/node/244924#linux-servers
echo "Setting ownership/permissions"
OWNER=$(whoami)
cd $APP_ROOT
chown -R $OWNER:$OWNER .
find . -type d -exec chmod u=rwx,g=rx,o=rx '{}' \;
find . -type f -exec chmod u=rw,g=r,o=r '{}' \;

# Use common files dir
echo "Removing any existing $APP_ROOT/sites/default/files, in favor of linking to common files dir in $BASE_DIR"
#   Try to remove symlink
[ -h $APP_ROOT/sites/default/files ] && rm $APP_ROOT/sites/default/files
#  Link to the app-files dir
ln -s $BASE_DIR/app-files $APP_ROOT/sites/default/files

cd $APP_ROOT/sites
find . -type d -name files -exec chmod ug=rwx,o=rx '{}' \;
for d in ./default/files/; do
 find $d -type d -exec chmod ug=rwx,o=rx '{}' \;
 find $d -type f -exec chmod ug=rw,o=r '{}' \;
done

# Set sensitive files/dirs as read-only
# TODO: secure .yml files?
chmod ug=r,o= $APP_ROOT/sites/default/settings.php
chmod ug=r,o= $APP_ROOT/sites/default/settings.local.php
chmod ug=r,o= $APP_ROOT/sites/development.services.yml
chmod ug=rx,o=x $APP_ROOT/sites/default

chmod +x $APP_ROOT

# Run deploy steps
if [ -f $VENDOR_DIR/bin/drush ]; then
  php $VENDOR_DIR/bin/drush updb -y
  php $VENDOR_DIR/bin/drush config:import -y
  php $VENDOR_DIR/bin/drush cr
fi

# Put the site on-line again.
if [ -f $VENDOR_DIR/bin/drush ]; then
  php $VENDOR_DIR/bin/drush sset system.maintenance_mode FALSE -y
fi

# Log the site status, right after deploy
if [ -f $VENDOR_DIR/bin/drush ]; then
  php $VENDOR_DIR/bin/drush st -y
fi
