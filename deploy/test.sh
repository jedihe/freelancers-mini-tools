#!/bin/bash

set -x

gittag () {
  git tag -a $1 -m "Tagging version $1"
}

[ -d src-repo ] && chmod -R u+w src-repo/{.git,*} && rm -r src-repo
[ -d dev-sites ] && chmod -R u+w dev-sites/* && rm -r dev-sites
[ -e fmt-deploy.config.json ] && rm fmt-deploy.config.json

if [[ "$1" == "--clean" ]]; then
  # Invoked only for cleaning, exit now.
  exit 0
fi

mkdir src-repo
cd src-repo
git init
echo "FMT-Deploy tests" > README.md
echo "# .htaccess" > .htaccess
echo "dev.1" > last-tag
git add .
git commit -m "First commit"
gittag dev.1

echo "

Line appended." >> README.md
git add .
git commit -m "Update README.md"

mkdir -p sites/default
echo "<?php
//Settings.php" > sites/default/settings.php
echo "dev.2" > last-tag
git add .
git commit -m "Adding fake settings.php"
gittag dev.2

echo "# robots.txt" > robots.txt
echo "dev.3" > last-tag
git add .
git commit -m "Adding robots.txt"
gittag dev.3

cd ..

FMT_DEPLOY_JSON=$(cat <<-SNIPPET
{
  "projects": {
    "my_project": {
      "repository": "$PWD/src-repo",
      "envs": {
        "dev": {
          "basedir" : "$PWD/dev-sites/my_project",
          "linkname": "public_html",
          "webroot": ".",
          "deploys-history": 2,
          "basic-auth": "my_user:my_pass"
        }
      }
    }
  }
}
SNIPPET
)

echo "$FMT_DEPLOY_JSON" > fmt-deploy.config.json

# Initialize
touch $PWD/dev-sites/my_project/fmt-deploy-ALLOW
./fmt-deploy.sh my_project dev.1

# Deploy dev.1
touch $PWD/dev-sites/my_project/fmt-deploy-ALLOW
./fmt-deploy.sh my_project dev.1

# Deploy dev.2
touch $PWD/dev-sites/my_project/fmt-deploy-ALLOW
./fmt-deploy.sh my_project dev.2

# Deploy dev.3
touch $PWD/dev-sites/my_project/fmt-deploy-ALLOW
./fmt-deploy.sh my_project dev.3
