# Deploying plaintrace_engineering to production

Production is a normal Frappe stack (this repo's `compose.yaml` with the MariaDB, Redis and no-proxy overrides) running **one
custom image** built on the production server: Frappe `v16.22.0` plus the `plaintrace_engineering` app. There is no ERPNext and no
registry. A single Jenkins job builds, backs up, deploys, migrates, tests and (if anything fails) rolls back.

```
you push the app to GitHub ──> click "Build with Parameters" in Jenkins ──> production runs the new version
```

Everything the job does is readable in [`Jenkinsfile`](./Jenkinsfile).

## What is where

| Thing | Location |
|---|---|
| Server | `walter` (`192.168.0.172`, Ubuntu, x86_64). SSH alias `walter` |
| Jenkins | `http://192.168.0.172:8080`, runs in a container with Docker access (see [Jenkins container](#the-jenkins-container)) |
| Production site | `http://192.168.0.172:8081` (LAN only), site name from `.env` |
| Settings and secrets | `/home/switchlabs/plaintrace/.env` (never in git; template: [`env.example`](./env.example)) |
| Deploy state | `/home/switchlabs/plaintrace/state/` (`current_tag`, `prev_tag`, `phase`, `last_backup`, `history.log`) |
| Pre-deploy backups | `/home/switchlabs/backups/plaintrace/<timestamp>/` (newest 14 kept) |
| Docker volumes | `plaintrace_sites` (site files) and `plaintrace_db-data` (database), among others |

Development is unaffected: the dev stack lives in `.devcontainer/`, on your Mac, and shares nothing with this.

## One-time setup

Do these once. (The Jenkins container change and the folders are already done.)

1. **GitHub token.** GitHub, Settings, Developer settings, Fine-grained tokens, Generate new token. Resource owner `soldermate`, repository
   access *only* `plaintrace_engineering`, permission **Contents: Read-only**. Set an expiry and put a reminder in your calendar: when it
   expires, every deploy fails at the first step with a clear message.
2. **Settings file.** On the server:
   ```bash
   scp deploy/env.example walter:plaintrace/.env      # or copy the contents by hand
   ssh walter 'chmod 600 ~/plaintrace/.env && nano ~/plaintrace/.env'
   ```
   Set `DB_PASSWORD` and `ADMIN_PASSWORD` to long random values. **Do not use spaces, quotes, `$` or `#` in them** (the file is read by
   both Docker Compose and the shell). Check `HTTP_PUBLISH_PORT`, `SMOKE_URL` and `PUBLIC_URL` use the server's LAN address.
3. **Jenkins credential.** Manage Jenkins, Credentials, (global), Add Credentials: kind *Secret text*, secret = the token, **ID `github-pat`**.
4. **Jenkins job.** New Item, name `plaintrace-deploy`, type *Pipeline*. Under Pipeline choose *Pipeline script from SCM*, SCM *Git*,
   repository `https://github.com/soldermate/frappe_docker.git`, branch `*/main`, script path `deploy/Jenkinsfile`. Save. (The fork is public, so no
   credential is needed for the checkout.)
5. **First run.** Build with Parameters: `APP_REF=develop`, tick **CREATE_SITE**. This builds the image, starts the stack and creates the
   site. It takes 10 to 20 minutes the first time.
6. **After the first run**, in the production site (`http://192.168.0.172:8081`, user `Administrator`, the `ADMIN_PASSWORD`):
   change the Administrator password; import the starter Part Classes with the Part Class Importer (download its template); set
   Library Settings; add your CAD Asset Sources and click Rebuild Index (private sources need their token); add the Digi-Key
   Service Connection and Test Connection; create a low-privilege user and API key for KiCad.

## Deploying an update

1. Push your work from the Mac: `git push` (the job deploys what is on GitHub, not what is on your Mac).
2. Jenkins, `plaintrace-deploy`, **Build with Parameters**: `APP_REF` = the branch or tag (default `develop`), leave `CREATE_SITE` unticked. Build.
3. Watch the console. Green means it is live and passed its checks.

What the job does, in order:

| Stage | What happens |
|---|---|
| Preflight | Checks disk space and that `APP_REF` exists on GitHub; turns it into an exact commit |
| Build image | Builds `plaintrace:<commit>`; the GitHub token is passed as a build secret and never stored in the image |
| Backup | Turns maintenance mode on, backs up the database and files, and copies the set to `~/backups/plaintrace/` |
| Deploy | Starts the new image, runs `bench migrate`, clears caches, turns maintenance off |
| Smoke test | Checks the site answers, `/login` works, `/kicad/v1/` returns 401 without a token, containers are healthy |

The site is in maintenance mode (visitors see "under maintenance") from the backup until the deploy finishes: usually a minute or two.

## If a deploy fails: automatic rollback

The failure block undoes what the deploy changed, based on how far it got:

| Failed during | Result |
|---|---|
| Preflight or build | Nothing changed on the running site |
| Backup | Maintenance mode is switched off |
| After the new image started, before migrate | The previous image is started again |
| During or after migrate | The previous image **and the pre-deploy database and files** are restored |

The build is then marked red and the log says `ROLLED BACK to plaintrace:<previous>`. Anything typed into the site between the backup and
the rollback is lost, which the maintenance-mode window keeps to nothing.

If the failure block itself fails, the state files tell you where things stand:
`cat ~/plaintrace/state/phase ~/plaintrace/state/prev_tag ~/plaintrace/state/last_backup`.

## Manual rollback and restore

Run these on the server (`ssh walter`). They use a checkout of this repo for the compose files:

```bash
git clone https://github.com/soldermate/frappe_docker.git ~/frappe_docker   # once
cd ~/frappe_docker
dc() { docker compose --project-name plaintrace --env-file ~/plaintrace/.env \
  -f compose.yaml -f overrides/compose.mariadb.yaml -f overrides/compose.redis.yaml -f overrides/compose.noproxy.yaml "$@"; }
```

**Go back to an earlier image** (only safe if the database still matches that version, i.e. no migration ran since; otherwise restore too):
```bash
docker image ls plaintrace                          # see the tags
sed -i 's/^CUSTOM_TAG=.*/CUSTOM_TAG=<tag>/' ~/plaintrace/.env && dc up -d
echo <tag> > ~/plaintrace/state/current_tag
```

**Restore a backup set** (replace the site's database and files with a pre-deploy backup):
```bash
SET=~/backups/plaintrace/<timestamp>; ls $SET
dc exec -T backend mkdir -p /tmp/restore
for f in $SET/*; do dc cp "$f" backend:/tmp/restore/; done
dc exec backend bench --site <SITE_NAME> restore /tmp/restore/<...>-database.sql.gz \
  --with-public-files /tmp/restore/<...>-files.tar --with-private-files /tmp/restore/<...>-private-files.tar \
  --db-root-password <DB_PASSWORD> --force
```
Keep `site_config_backup.json` from each set: it holds the site's `encryption_key`. Without it, stored passwords (the Digi-Key secret,
source tokens) cannot be decrypted after a restore onto a new site. The backups sit on the same ZFS pool as everything else, so they
protect against mistakes, not against losing the disks: copy them somewhere else now and then.

## Read this before exporting fixtures

`plaintrace_engineering/hooks.py` declares `fixtures` for **Engineering Attribute** and **Part Class**. There is no `fixtures/` folder in the
app today, so nothing is applied. But if you ever run `bench export-fixtures` in dev and commit the files, then on **every deploy**
(`bench migrate`) Frappe imports them and **overwrites production's matching Part Classes and Engineering Attributes** (naming schemes,
descriptions, attribute template rows, mandatory and Sync-to-CAD flags, Distributor Names, Value Patterns). Records that exist only on
production are not deleted; Parts, CAD data, settings and users are never touched. Only commit fixture files if dev should overwrite
production's taxonomy.

## The Jenkins container

Jenkins runs from a small image on top of the official one (adds the Docker CLI, Compose and buildx): [`jenkins/Dockerfile`](./jenkins/Dockerfile).
The container gets the host's Docker socket, the `docker` group, and two folders mounted at the **same path** as on the host (so paths in
the pipeline mean the same thing inside and outside):

```bash
docker build -t jenkins-docker:latest deploy/jenkins
docker run -d --name jenkins --restart always \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock --group-add 988 \
  -v /home/switchlabs/plaintrace:/home/switchlabs/plaintrace \
  -v /home/switchlabs/backups:/home/switchlabs/backups \
  jenkins-docker:latest
```
(`988` is the server's `docker` group id: `getent group docker`.) Jenkins' own data lives in the `jenkins_home` volume and survives recreating
the container. Access to the Docker socket makes Jenkins root-equivalent on the server, so keep it LAN-only. To update Jenkins,
rebuild with `--pull` and run the same `docker run` after `docker rm -f jenkins`.

## Frappe version

Production is pinned to Frappe `v16.22.0`, matching the dev bench (`FRAPPE_REF` in the `Jenkinsfile` and `deploy/Containerfile`).
`version-16` on GitHub moves ahead of it, so deploys do not silently pick up newer Frappe. To upgrade both together: update the dev bench
(`bench update`), test, then change `FRAPPE_REF` and deploy.

## What this setup changes compared with stock frappe_docker

- **Frappe is pinned** (see above) instead of tracking `version-16`.
- **nginx serves `/kicad/` without the trailing-slash redirect.** Frappe's stock nginx config redirects any URL ending in `/` (so
  `/kicad/v1/` became a 301 to `/kicad/v1`). KiCad requests the library root with the slash and may not follow a redirect, so
  `deploy/Containerfile` inserts a small `location /kicad/` block into the image's nginx template. The build fails if the insert does not
  land, and the smoke test checks that `/kicad/v1/` answers 401 directly (not 301).
- **The compose file's `platform: linux/amd64` pin is left alone**, which matches this server. (To try the stack on an arm64 machine
  such as an Apple-silicon Mac, remove those lines from a scratch copy only.)
- **Compose reads the shell environment before the `.env` file.** The pipeline loads `.env` into its shell, so whenever it changes
  `CUSTOM_TAG` it also exports the new value. Keep that in mind if you add steps that edit `.env`.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Fails at "Preflight": *cannot read ... github-pat* | Token expired, wrong, or missing *Contents: Read* on the repo |
| Fails at "Preflight": *not a branch or tag* | Branch not pushed yet, or a typo in `APP_REF` |
| Build fails fetching the app | Same token problem, or GitHub unreachable from the server |
| *no current deployment recorded* | The first run has not happened yet: tick `CREATE_SITE` |
| *site ... already exists* | Untick `CREATE_SITE` |
| Smoke test: `/kicad/v1/` is not 401 | The app did not load: read the backend logs (`dc logs backend --tail 100`) |
| Site says "under maintenance" for a long time | A deploy died mid-way: check `state/phase`, then `docker exec ... set-maintenance-mode off` |
