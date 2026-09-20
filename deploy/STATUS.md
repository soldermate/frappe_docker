# Production deployment: status notes

Last updated: 2026-09-20 (end of the first session). Read [`README.md`](./README.md) for how everything works; this file is the
"where did we leave off" log.

## Where things stand

**Production is live** at `http://192.168.0.172:8081` (LAN only) on the server `walter`, deployed by Jenkins build #1 from
`soldermate/plaintrace_engineering` `develop` at commit `face24d` (Frappe 16.22.0, no ERPNext). It passed its smoke test, and the
database and Redis are not reachable from the LAN.

Done:
- **Server checks** (Ubuntu 24.04, x86_64, 12 cores, 7.5 GB RAM + 4 GB swap, Docker 29, ZFS storage, outbound access to GitHub, Docker Hub,
  GitLab, Digi-Key all fine).
- **Jenkins made able to run Docker.** It was a stock `jenkins/jenkins` container with no Docker access. It is now the custom image in
  `deploy/jenkins/Dockerfile` (Docker CLI + Compose + buildx, the host's Docker socket, group 988, and the folders
  `~/plaintrace` and `~/backups` mounted at the same paths). Jenkins 2.524, same data volume (`jenkins_home`), nothing lost.
  Backup of the old volume: `~/backups/jenkins_home-20260920-195923.tgz`. The old container is stopped, not removed: `jenkins-old`.
- **Deploy files** written, rehearsed on the Mac, committed and pushed (`deploy/`): `Jenkinsfile`, `Containerfile`, `env.example`,
  `jenkins/Dockerfile`, `README.md`.
- **Server settings file** `~/plaintrace/.env` created with generated passwords (mode 600, never shown in chat). The temporary
  `ADMIN_PASSWORD` line has been deleted after first login; the password is in the owner's password manager.
- **Jenkins**: credential `github-pat` (Secret text, fine-grained token, **expires 19 November 2026**) and the job `plaintrace-deploy`
  (Pipeline from SCM, this repo, `main`, `deploy/Jenkinsfile`, parameters `APP_REF` and `CREATE_SITE` defined in the job).
- **First deploy** (build #1, `CREATE_SITE` ticked) succeeded in about 4 minutes.
- **Phase 3** (site set-up by hand in the UI) done by the owner: own user created, classes imported, Library Settings, CAD sources, Digi-Key
  connection. Not yet confirmed: that KiCad, pointed at production, loads the library (check this first tomorrow).

## What was rehearsed on the Mac (not yet on the server)

The pipeline's shell snippets were run unchanged against a scratch stack: first-run site creation, an update, and a forced rollback with
database restore (the change made after the backup was undone and the previous image came back). The rehearsal found and fixed two real
bugs: Compose lets the shell environment override `.env` (so the tag change was ignored), and nginx redirected `/kicad/v1/` (now
passed through by an nginx block baked into the image).

## Still to do (tomorrow)

**Phase 4, the rest:**
1. **Ordinary update.** Push a tiny change to the app's `develop`, click *Build with Parameters* (leave `CREATE_SITE` off) and check the
   Backup, Deploy and Smoke stages on the real server. This is the first time the Backup and Deploy stages run in Jenkins.
2. **Rollback drill (the important one).** Push a scratch branch containing a patch that raises during `migrate`, deploy it, and confirm:
   the build is red, the log says `ROLLED BACK to plaintrace:<previous>`, production is on the previous image with data intact, and
   maintenance mode is off. (`state/phase`, `state/prev_tag`, `state/last_backup` under `~/plaintrace/state/` show what happened.)
   Also try one that fails *before* migrate (e.g. a bad branch name) to see it change nothing.
3. **Restore drill (optional but wise).** Restore the newest backup set from `~/backups/plaintrace/` into a scratch site, and check that a
   stored password (the Digi-Key secret) still decrypts, which proves `site_config_backup.json` is being kept.

**Smaller items:**
- Confirm KiCad loads the library from production (API key of a low-privilege user).
- Scheduled nightly backup: a second small Jenkins job (not built). Until then, the only backups are the ones each deploy takes.
- Copy backups somewhere other than the same ZFS pool now and then.
- Check the firewall from outside the LAN (needs root on the server to read `ufw`; the port is bound to the LAN address only).
- Remove the old `jenkins-old` container once you are happy with the new Jenkins (`docker rm jenkins-old`).
- Docs commit `3f08714` (ADMIN_PASSWORD notes) may still be unpushed: `git -C ~/Code/frappe_docker status -sb`.
- Calendar reminder for the GitHub token expiry (19 Nov 2026).

## Things worth remembering

- **Deploys build what is on GitHub**, not your Mac. Push first.
- **Never commit exported fixtures** unless dev should overwrite production's Part Classes and Engineering Attributes on every deploy
  (`hooks.py` declares them; no fixture files exist today).
- **Production has no outgoing email.** Password reset by email cannot work; use `bench ... set-admin-password` (README, troubleshooting).
- **Frappe is pinned to v16.22.0** (`FRAPPE_REF` in the `Jenkinsfile`); the base image's Python is 3.14.7 while the dev bench has 3.14.2.
- The Mac-side rehearsal harness was scratch work and is not kept in the repo. If needed again, it extracts each `bash('''...''')` snippet
  from the `Jenkinsfile` and runs it against a scratch compose project (gotchas: macOS `sed -i` differs, the compose file pins
  `linux/amd64`, and bench needs `host/org/repo` git URLs).
