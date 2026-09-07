#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$HOME/fullstack-compose"
FRONTEND_DIR="$REPO_ROOT/frontend"
DIST_DIR="$FRONTEND_DIR/dist"

DEPLOY_ROOT="/var/www/fullstack-compose"
RELEASES_DIR="$DEPLOY_ROOT/releases"
CURRENT_LINK="$DEPLOY_ROOT/current"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

echo "===== FRONTEND DEPLOY SAFETY CHECK ====="

[ -d "$REPO_ROOT" ] || fail "repo root not found: $REPO_ROOT"
[ -d "$FRONTEND_DIR" ] || fail "frontend directory not found: $FRONTEND_DIR"

[ -f "$FRONTEND_DIR/package.json" ] \
    || fail "package.json not found"

[ -f "$FRONTEND_DIR/package-lock.json" ] \
    || fail "package-lock.json not found"

[ -d "$DEPLOY_ROOT" ] \
    || fail "deploy root not found: $DEPLOY_ROOT"

[ -d "$RELEASES_DIR" ] \
    || fail "releases directory not found: $RELEASES_DIR"

[ -L "$CURRENT_LINK" ] \
    || fail "current is not a symbolic link: $CURRENT_LINK"

sudo -n true \
    || fail "passwordless sudo is not available"

CURRENT_RELEASE="$(readlink -f "$CURRENT_LINK")"

case "$CURRENT_RELEASE" in
    "$RELEASES_DIR"/*)
        ;;
    *)
        fail "current points outside releases directory: $CURRENT_RELEASE"
        ;;
esac

echo "repo root:       $REPO_ROOT"
echo "frontend dir:    $FRONTEND_DIR"
echo "deploy root:     $DEPLOY_ROOT"
echo "releases dir:    $RELEASES_DIR"
echo "current release: $CURRENT_RELEASE"

echo
echo "===== BUILD FRONTEND ====="

cd "$FRONTEND_DIR"

npm ci
npm run build

echo
echo "===== VALIDATE BUILD OUTPUT ====="

[ -d "$DIST_DIR" ] \
    || fail "dist directory not found after build"

[ -f "$DIST_DIR/index.html" ] \
    || fail "dist/index.html not found after build"

[ -s "$DIST_DIR/index.html" ] \
    || fail "dist/index.html is empty"

echo "build output: $DIST_DIR"
echo "index.html: OK"

echo
echo "Build validation: OK"
echo "Build phase complete."

echo
echo "===== PREPARE NEW RELEASE ====="

RELEASE_ID="$(date '+%Y%m%d-%H%M%S')"
NEW_RELEASE="$RELEASES_DIR/$RELEASE_ID"

case "$NEW_RELEASE" in
    "$RELEASES_DIR"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9])
        ;;
    *)
        fail "invalid release path: $NEW_RELEASE"
        ;;
esac

[ ! -e "$NEW_RELEASE" ] \
    || fail "release already exists: $NEW_RELEASE"

echo "release id:  $RELEASE_ID"
echo "new release: $NEW_RELEASE"

echo
echo "===== CREATE NEW RELEASE ====="

sudo mkdir "$NEW_RELEASE"

[ -d "$NEW_RELEASE" ] \
    || fail "failed to create release directory"

sudo cp -a "$DIST_DIR/." "$NEW_RELEASE/"

echo
echo "===== VALIDATE NEW RELEASE ====="

[ -f "$NEW_RELEASE/index.html" ] \
    || fail "new release index.html not found"

[ -s "$NEW_RELEASE/index.html" ] \
    || fail "new release index.html is empty"

echo "new release: $NEW_RELEASE"
echo "index.html: OK"

echo
echo "Release creation: OK"
echo "Release prepared; activation not started yet."

echo
echo "===== PREPARE ATOMIC SWITCH ====="

OLD_RELEASE="$(readlink -f "$CURRENT_LINK")"
SWITCH_LINK="$DEPLOY_ROOT/current.next"
ROLLBACK_LINK="$DEPLOY_ROOT/current.rollback"

case "$OLD_RELEASE" in
    "$RELEASES_DIR"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9])
        ;;
    *)
        fail "old release path is invalid: $OLD_RELEASE"
        ;;
esac

[ -f "$OLD_RELEASE/index.html" ] \
    || fail "old release index.html not found"

[ ! -e "$SWITCH_LINK" ] && [ ! -L "$SWITCH_LINK" ] \
    || fail "temporary switch path already exists: $SWITCH_LINK"

[ ! -e "$ROLLBACK_LINK" ] && [ ! -L "$ROLLBACK_LINK" ] \
    || fail "temporary rollback path already exists: $ROLLBACK_LINK"

echo "old release: $OLD_RELEASE"
echo "new release: $NEW_RELEASE"

echo
echo "===== ATOMIC SWITCH ====="

sudo ln -s "$NEW_RELEASE" "$SWITCH_LINK"
sudo mv -T "$SWITCH_LINK" "$CURRENT_LINK"

ACTIVE_RELEASE="$(readlink -f "$CURRENT_LINK")"

[ "$ACTIVE_RELEASE" = "$NEW_RELEASE" ] \
    || fail "current did not switch to new release"

echo "current release: $ACTIVE_RELEASE"

echo
echo "===== POST-DEPLOY HEALTH CHECK ====="

FRONTEND_OK=0
API_OK=0

curl -fsS -o /dev/null http://127.0.0.1/ \
    && FRONTEND_OK=1

curl -fsS -o /dev/null http://127.0.0.1/api/users \
    && API_OK=1

if [ "$FRONTEND_OK" -eq 1 ] && [ "$API_OK" -eq 1 ]; then
    echo "frontend health: OK"
    echo "api health:      OK"
    echo "deployment: SUCCESS"
else
    echo "health check failed"
    echo "starting rollback to: $OLD_RELEASE"

    sudo ln -s "$OLD_RELEASE" "$ROLLBACK_LINK"
    sudo mv -T "$ROLLBACK_LINK" "$CURRENT_LINK"

    ROLLED_BACK_RELEASE="$(readlink -f "$CURRENT_LINK")"

    [ "$ROLLED_BACK_RELEASE" = "$OLD_RELEASE" ] \
        || fail "rollback switch failed"

    echo "rollback release: $ROLLED_BACK_RELEASE"
    fail "deployment failed and was rolled back"
fi

echo
echo "===== DEPLOYMENT COMPLETE ====="
echo "previous release: $OLD_RELEASE"
echo "current release:  $(readlink -f "$CURRENT_LINK")"
