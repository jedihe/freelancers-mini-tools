#!/bin/bash

# fmt-deploy.sh
#
# Part of freelancers-mini-tools v0.1
#
# TODO:
#
# - Require valid values for ALL(?) variables.
# - Implement require_env_setting/require_project_setting, to fail early if
#   some param is missing.
# - Resolve str_pad issue with multi-byte characters?
# - Refactor to rely on trapping 'exit' + check if deploy is in progress, in
#   order to mark a deploy as failed.
# - Analyze if basic rollback functionality is doable, incl. DB restore, etc.
# - Compress previous deploys as .tar.gz. This should prevent super-high inode
#   usage.

if [ $# -lt 2 ]; then
  cat <<-HELP
  You must provide *all* the parameters

  Usage:
    /path/to/fmt-deploy.sh project_name tag

  Requirements:
    - PHP available on the CLI.
    - Set up fmt-deploy.config.json, in the same dir as this script.
    - Tag must be formatted as ENVIRONMENT.SUFFIX, with only one '.' in it.
HELP
  exit 1
fi

set -ex

# Banner symbols; falls back to $H_
H1="="
H2="+"
H3=":"
H_="x"

function banner() {
  set +x
  __banner_line "$1" $2
  __banner_line "$(echo -n $(date))" $2
  set -x
}

function __banner_line() {
  DECOR=${2:-$H_}
  echo $(php -r "echo str_pad(\" $1 \", 100, \"$DECOR\", STR_PAD_BOTH);")
}

function read_project_setting() {
  #jq -r ".projects.$PROJECT.repository" fmt-deploy.config.json
  echo $(php -r "echo json_decode(file_get_contents(\"$JSON_CONFIG\"), TRUE)[\"projects\"][\"$PROJECT\"][\"$1\"];")
}

function read_env_setting() {
  local TARGET_ENV=${TAG%.*}
  local SETTING=$1
  local _DEFAULT=$2
  local _VALUE=$(php -r "echo json_decode(file_get_contents(\"$JSON_CONFIG\"), TRUE)[\"projects\"][\"$PROJECT\"][\"envs\"][\"$TARGET_ENV\"][\"$SETTING\"];")
  _VALUE=${_VALUE:-$_DEFAULT}
  echo $_VALUE
}

function verify_git_connectivity() {
  # Taken from https://superuser.com/q/227509
  git ls-remote --heads $REPO_URL 2>&1
  local _RETVAL=$?
  if [ $_RETVAL -ne 0 ] && [[ $REPO_URL =~ ^"git@" ]]; then
    # Run SSH agent, see https://serverfault.com/a/672386
    eval "$(ssh-agent -s)"
  fi
}

function initialize() {
  banner "Repo clone dir not found, initializing it!" $H1
  verify_git_connectivity
  git clone --no-checkout $REPO_URL $REPO_CLONE_DIR

  echo "Ensuring other dirs exist..."
  [ ! -d "$BASE_DIR/secrets" ] &&
    mkdir -p "$BASE_DIR/secrets" &&
    echo "Place files with *secrets* here." > "$BASE_DIR/secrets/README"

  [ ! -d "$BASE_DIR/app-files" ] &&
    mkdir -p "$BASE_DIR/app-files" &&
    echo "Place user-generated files here." > "$BASE_DIR/app-files/README"

  banner "Finished initializing repository"
  cat <<-HELP
Next steps:
===========
* Add secrets-only files under $BASE_DIR/secrets/ dir.
* Add $BASE_DIR/fmt-deploy-custom.sh, customize as needed and make it executable.
* Import DB dump into DB for the site.
* Upload user-generated files to $BASE_DIR/app-files/ dir.
* Add empty file at $BASE_DIR/fmt-deploy-ALLOW; this file must be created before
  running $0, *everytime*.
* Run (remove leading #):
# $0 $PROJECT $TAG

HELP
  printf "\n\n"
  # UNTESTED: logging mechanism may hang sometimes, sleep 2 tries to fix that.
  sleep 2
  exit 0
}

function purge_old_failed_deploys() {
  purge_old_deploys 'FAILED--' 2
}

function purge_old_deploys() {
  local _TARGET_ENV=${TAG%.*}
  local _PREFIX=${1:-$_TARGET_ENV}
  local _THRESHOLD=${2:-2}
  # Remove the directories for *all* previous deploys. Previous deploys may
  # only be preserved as archives (see below).
  # For "ls -d */" construct, see https://stackoverflow.com/a/14352330/6072846
  local _OLD_DEPLOYS=$(ls -1 -d $DEPLOYS_DIR/*/ | grep "deploys/$_PREFIX" | sort --version-sort | head -n -1)
  # Had to count line-starts (grep -c "^"), since wc -l counts new-line chars!
  local _NUM_OLD_DEPLOYS=$(echo -n "${_OLD_DEPLOYS}" | grep -c "^")
  if [ ${_NUM_OLD_DEPLOYS} -gt 0 ]; then
    banner "Purging ${_NUM_OLD_DEPLOYS} deploys for prefix $_PREFIX..." $H2
    __safe_purge_dirs  ${_OLD_DEPLOYS}
  fi

  # WARNING: ensure that at least 2 deploy archives are preserved!
  # (current/last + the previous one)
  [ $_THRESHOLD -lt 2 ] && _THRESHOLD=2
  local _OLD_DEPLOYS_ARCHIVES=$(ls -1 $DEPLOYS_DIR/*.tar.gz | grep "deploys/$_PREFIX" | sort --version-sort | head -n -"$_THRESHOLD")
  local _ARCHIVE
  for _ARCHIVE in $_OLD_DEPLOYS_ARCHIVES; do
    rm $_ARCHIVE
  done
}

function __safe_purge_dirs() {
  local _DIR
  for _DIR in $@; do
    # Safely delete symlinks.
    find "$_DIR" -type l -exec chmod +w {} \; -exec rm {} \;
    # Make remaining inodes writable.
    chmod +w -R "$_DIR"
    # Do a recursive deletion.
    rm -r "$_DIR"
  done
}

function update_repo_clone() {
  echo "Fetching updates for $1..."
  cd $1
  verify_git_connectivity
  git fetch origin --tags
}

function require_tag_in_repo() {
  cd $1

  local REQUIRED_TAG=$2
  local FETCHED_TAG=$(git tag --list "$REQUIRED_TAG")
  if [ "$FETCHED_TAG" != "$REQUIRED_TAG" ]; then
    banner "Error: tag '$REQUIRED_TAG' not found in $1." $H3
    banner "Removing $PROJECT/fmt-deploy-ALLOW and aborting..." $H3
    rm $ALLOW_FILE
    # UNTESTED: logging mechanism may hang sometimes, sleep 2 tries to fix that.
    sleep 2
    exit 1
  fi
}

# Required here, so that logging can be started.
JSON_CONFIG="$(dirname $(readlink -f $0))/fmt-deploy.config.json"
PROJECT=$1
TAG=$2

BASE_DIR=$(read_env_setting basedir)
DEPLOYS_DIR="$BASE_DIR/deploys"
mkdir -p $DEPLOYS_DIR ||
  { echo "Can not create $DEPLOYS_DIR. Aborting!." ; exit 1 ; }

# Log all the output to a file
# See https://stackoverflow.com/a/8703001/6072846
exec > >(tee -a $DEPLOYS_DIR/deploy-log.txt) 2>&1

# No-op assignments, so that the log capture gets to record the values.
JSON_CONFIG="$JSON_CONFIG"
PROJECT=$PROJECT
TAG=$TAG
BASE_DIR="$BASE_DIR"
DEPLOYS_DIR="$DEPLOYS_DIR"

ENVIRONMENT=${TAG%.*}
LINK_PATH="$BASE_DIR/$(read_env_setting linkname public_html)"
WEBROOT=$(read_env_setting webroot .)
APP_ROOT="$BASE_DIR/$WEBROOT"

REPO_URL=$(read_project_setting repository)
REPO_CLONE_DIR="$BASE_DIR/repo"
ALLOW_FILE="$BASE_DIR/fmt-deploy-ALLOW"

function deploy_tag() {
  local _REPO_SRC=$1
  local _TAG=$2
  local _DEPLOYS_DIR=$3
  local _LINK_PATH=$4

  mkdir $_DEPLOYS_DIR/$_TAG
  cd $_DEPLOYS_DIR/$_TAG
  git --git-dir=$_REPO_SRC/.git checkout $_TAG '*'

  # Run optional, app-specific, script
  if [ -x "$BASE_DIR/fmt-deploy-custom.sh" ]; then
    banner "Found fmt-deploy-custom.sh, executing it..." $H2
    # Prevent errors in custom.sh to infect the main process.
    set +e
    $BASE_DIR/fmt-deploy-custom.sh "$_DEPLOYS_DIR/$_TAG" "$BASE_DIR" "$_TAG" "$_LINK_PATH"
    local _CUSTOM_SH_RETVAL=$?
    # Back to the initial state.
    set -e
  fi

  set +e
  set_up_basic_auth
  local _BASIC_AUTH_RETVAL=$?
  set -e

  if [ $_CUSTOM_SH_RETVAL -ne 0 ] || [ $_BASIC_AUTH_RETVAL -ne 0 ]; then
    mark_failed_deploy
    purge_old_failed_deploys
    # UNTESTED: logging mechanism may hang sometimes, sleep 2 tries to fix that.
    sleep 2
    exit 1
  fi

  # Successful deploy, create archive for it.
  cd $_DEPLOYS_DIR
  banner "Creating archive for tag $_TAG..." $H3
  tar -zcf $_TAG.tar.gz $_TAG
  cd -

  if [ -e $_LINK_PATH ]; then
    # If removing, also do ln right away, to prevent the webserver from
    # auto-creating the dir.
    rm -f $LINK_PATH && ln -s $_DEPLOYS_DIR/$_TAG $_LINK_PATH
  else
    ln -s $_DEPLOYS_DIR/$_TAG $_LINK_PATH
  fi

  local _CUR_COMMIT=$(git --git-dir=$_REPO_SRC/.git rev-list -1 $_TAG)
  echo "$(date): Deployed tag $_TAG, from commit $_CUR_COMMIT" >> $_DEPLOYS_DIR/deploy-history.txt
}

function mark_failed_deploy() {
  banner "Error: couldn't finish deploy for tag $_TAG'. Aborting" $H2
  local _FAILED_DEPLOY_SUBDIR="FAILED--$(date +%F--%H-%M-%S)--$_TAG"
  banner "Keeping deploy dir as $_FAILED_DEPLOY_SUBDIR" $H3
  mv $DEPLOYS_DIR/$TAG $DEPLOYS_DIR/$_FAILED_DEPLOY_SUBDIR
}

function set_up_basic_auth() {
  local _BASIC_AUTH=$(read_env_setting "basic-auth")

  if [ "$_BASIC_AUTH" != "" ] && [ ! -f $DEPLOYS_DIR/$TAG/$WEBROOT/.htaccess ]; then
    banner "Error: $TAG/$WEBROOT/.htaccess not found, add it or remove basic-auth"
    return 1
  fi

  if [[ $_BASIC_AUTH =~ [a-zA-Z0-9]+:[a-zA-Z0-9]+ ]]; then
    # Snippet taken from https://stackoverflow.com/a/677212/6072846
    if command -v htpasswd; then
      local _USER=${_BASIC_AUTH%:*}
      local _PASS=${_BASIC_AUTH#*:}
      # Command found in https://blog.sleeplessbeastie.eu/2020/02/26/how-to-generate-password-digest-for-basic-authentication-of-http-users/
      local _BASIC_AUTH=$(echo "${_PASS}" | htpasswd -i -n "${_USER}")
      echo $_BASIC_AUTH > $BASE_DIR/secrets/htpasswd

      local _BASIC_AUTH_SNIPPET=$(cat <<-SNIPPET
# Begin: Automatically added by fmt-deploy.
AuthType Basic
AuthName "$_USER"
AuthUserFile "$BASE_DIR/secrets/htpasswd"
require valid-user
# End: Automatically added by fmt-deploy.

SNIPPET
)
      # Prepend new data by printing the existing content last.
      local _HTACCESS_PATH="$DEPLOYS_DIR/$TAG/$WEBROOT/.htaccess"
      set +x
      echo "Prepending Basic Auth directive to .htaccess"
      echo -e "$_BASIC_AUTH_SNIPPET\n$(cat $_HTACCESS_PATH)" > $_HTACCESS_PATH
      set -x
    else
      banner "Error: missing htpasswd, skipping basic-auth setup." $H3
      return 1
    fi
  fi
}

banner "Beginning Deploy!"

if [ ! -d "$REPO_CLONE_DIR" ]; then
  initialize
fi

if [ ! -f $ALLOW_FILE ]; then
  banner "Error: Allow file ($PROJECT/fmt-deploy-ALLOW) not found. Aborting deploy." $H3
  # UNTESTED: logging mechanism may hang sometimes, sleep 2 tries to fix that.
  sleep 2
  exit 1
else
  # WARNING: ensure ALLOW_FILE is always removed.
  rm $ALLOW_FILE

  update_repo_clone $REPO_CLONE_DIR
  require_tag_in_repo $REPO_CLONE_DIR $TAG

  if [ ! -d "$DEPLOYS_DIR/$TAG" ]; then
    deploy_tag $REPO_CLONE_DIR $TAG $DEPLOYS_DIR $LINK_PATH
    # Purging will only happen if deploy_tag succeeds, as failure there
    # triggers an early exit.
    purge_old_deploys $ENVIRONMENT $(read_env_setting "deploys-history" 2)
  else
    banner "Tag $TAG already deployed." $H2
  fi

  banner "Deploy finished!"
fi

printf "\n\n"

# UNTESTED: logging mechanism may hang sometimes, sleep 2 tries to fix that.
sleep 2
exit 0
