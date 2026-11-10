# Codex Cloud development stack

This setup is development-only and based on commit
`951b4ac29ca1c7f6a04edc94f60a6f34294f7d7c`. Production Compose,
Dockerfiles, deployment workflows, IAM and infrastructure are not used or changed
by these scripts. All credentials in `dev/local.env` are PUBLIC DUMMY VALUES.

## Prerequisites

Use a trusted Linux amd64 Cloud task with Bash, Python 3, ripgrep, Git, a local
Docker Unix socket and Docker Compose >=2.24.4. Docker 29.9.2/rootless and
Compose 2.40.3 were tested. BuildKit secret mounts, registry/npm access, the
platform proxy configuration and CA trust must work. No host npm installation,
existing application images, containers, database volume or npm cache is required.
Existing caches may accelerate builds; an entirely fresh Cloud task and its
published hook configuration still need separate validation.

Node 22.22.0 and MySQL 9.7.2 use reviewed amd64 image digests. npm ci uses the
tracked lockfiles with integrity verification. Build labels/tags record HEAD;
uncommitted source changes are included, so HEAD alone does not identify a dirty
build. Digest pinning is not a vulnerability scan or a byte-identical-build claim.

`CODEX_PROXY_CERT` must identify a readable public PEM CA bundle without private
keys. Otherwise the host system CA bundle is used. npm receives it only through
a BuildKit secret mount, with TLS verification enabled. It is not copied into
image layers. Docker retains its platform proxy configuration; the wrapper
forwards only explicit development inputs and proxy variables. Buildx creates
new private working directories under /tmp during builds; no previous session
files are inputs to installation, startup, tests or rollback.

## Install and cold start

Select the project and host port consistently for every command. Choose a new
project for a fresh database; never delete an existing database volume to reset it.

```sh
export CODEX_DEV_PROJECT=fullstack-codex-dev-example001
export CODEX_DEV_FRONTEND_PORT=3200
./dev/compose.sh check-port
./install.sh
./start.sh --check
./start.sh
./start.sh --test
```

`install.sh` validates, pulls pinned MySQL and builds both application images.
`start.sh` starts **all three services** with health ordering, no image pull or
build, no forced recreation and no cleanup. Repeated starts preserve unchanged
container IDs and named volumes. Image/configuration changes may recreate only
services in the selected project. Do not reuse another workload's project name.
Failures preserve containers, logs and data; inspect the selected project.

The project defaults to `fullstack-codex-dev` and must use that prefix followed
by lowercase alphanumeric suffixes. The host port defaults to 3000 and must be a
canonical integer in 1024-65535, without signs, spaces or leading zeros. Only
`127.0.0.1:<selected port>` is published. Container port 3000 stays fixed.
Port preflight rejects another project/process before creation; the selected
project may retain its own existing frontend port. Docker performs the final
exclusive bind, so a concurrent allocation after preflight can still fail safely.

React is at `http://127.0.0.1:<selected port>`; `/api/health` and `/api/users`
proxy to internal Express `/health` and `/users`. Backend and MySQL have no host
publications. All three share an internal application network. Only frontend
also joins a non-internal ingress bridge: **frontend gains an outbound route,
relaxing strict network isolation**. Loopback publication is not authentication.
Vite's explicit allowed-host policy is retained; external preview hosts need
separate review. No relay, host networking or host Docker socket is used.

## Safety gates and tests

Every operation uses one validator in `dev/compose.sh`; `start.sh` delegates
check/start/test operations to it. Unknown service/resource/build/security fields
fail closed. Docker API socket integration, privilege/capability additions,
custom security options, host namespaces, devices, extra mounts/networks,
unexpected credentials/images and backend/MySQL publications are rejected.
Remote Docker selectors and foreign resource ownership are rejected.

```sh
./dev/compose.sh self-test
./start.sh --self-test
```

These commands validate the approved model and run in-memory negative security
variants without creating services. `--check` only renders/validates configuration.
`--test` checks host HTTP, health, proxy, CRUD, cleanup regressions, lint and build.
Before first startup completes for a newly created named volume, initialization
must contain exactly the ten seed emails. Existing volumes are not reset: normal
tests require seed presence and allow additional persistent rows. A previously
created volume from a failed setup is treated conservatively as existing.

CRUD uses a unique UUID email and cleans up by that exact email, even after a
POST response status/JSON/assertion failure. It validates numeric IDs and never
deletes unrelated records. Cleanup retries are bounded; an unavailable API can
prevent cleanup, in which case the original error and cleanup error/email are
both reported for investigation. There is no automatic bulk delete or seed replay.

Development Dockerfiles copy explicit application paths and manifests only;
root .env, .env.local, .npmrc and incidental context files are not copied.
A build preflight rejects symlinks and unreviewed/credential-like filenames or
file types inside copied source/public trees. New asset types need explicit
review. Application source and dependency lifecycle scripts remain trusted code:
no filename policy can detect a secret deliberately embedded in a source file.
Production .dockerignore files are unchanged. The frontend image generates its
own node_modules/dist lint exclusions. Source edits require a selected-project
image rebuild; there is no live host source-code mount.

## Selected-project diagnostics and shutdown

Require explicit selection before operational commands, even when using defaults:

```sh
: "${CODEX_DEV_PROJECT:?Select the reviewed development project}"
: "${CODEX_DEV_FRONTEND_PORT:?Select its host frontend port}"
./dev/compose.sh ps --all
./dev/compose.sh logs --tail 100
./dev/compose.sh stop
```

Stop preserves all containers, networks, images and volumes. The wrapper does
not expose down, resource removal, prune or volume-deletion commands.

## Versioned rollback

Rollback requires a clean, committed working tree and a fully reviewed Git
revision that contains all ten development files and compatible application
manifests/lockfiles. Do not use session copies or guess a revision. If there is
uncommitted work, stop and arrange its separate review/preservation; never use a
forced reset or automatic stash. Record the current revision and selected project.

```sh
: "${CODEX_DEV_PROJECT:?Select the development project to roll back}"
: "${CODEX_DEV_FRONTEND_PORT:?Select its host port}"
: "${REVIEWED_REVISION:?Provide the full reviewed rollback commit}"
git status --porcelain
# Continue only when the preceding output is empty.
git rev-parse --verify "${REVIEWED_REVISION}^{commit}"
git cat-file -e "${REVIEWED_REVISION}:dev/compose.sh"
# Confirm that revision contains every development file and inspect its complete
# manifest/lockfile and Compose changes before switching. No production command
# or infrastructure operation is part of this procedure.
git switch --detach "$REVIEWED_REVISION"
./install.sh
./start.sh --check
# Review the selected project, image names, volume name, networks and port first.
./start.sh
./start.sh --test
```

Never downgrade MySQL or apply schema-incompatible revisions against an existing
volume. If the database contract differs, stop for a separate reviewed plan or
use a new isolated project/volume. Compatible rollback retains the selected
project's data volume and does not touch any other project. Restoring older
dependency revisions can reintroduce advisories and requires security review.
No environment settings, published hooks or production rollback paths are changed.

## Dependency and validation scope

Phase 5 patched body-parser 2.4.0, proxy-addr 2.0.8, qs 6.16.1,
source-map-js 1.2.2 and Vite 8.2.4. Both lockfiles returned zero npm advisories at
that check; advisory data can change. Future production builds also consume these
tracked dependency changes, but development scripts do not deploy them. The
backend npm test command remains an existing failure placeholder; the development
integration/cleanup checks are not a full application or browser E2E test suite.
Fresh-project validation on an existing daemon is distinct from fresh Cloud task
provisioning or an uncached build. Commit all ten development files before
claiming a Git-only checkout contains the setup. Do not publish without separate
review of the actual Cloud install/start hook mapping.
