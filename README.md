# ratmachine (a testbuild for experimenting)

![Logo](res/logo.png)  
[![Amber Framework](https://img.shields.io/badge/using-amber_framework-orange.svg)](https://amberframework.org)

![Screenie](res/screenie.png)
Ratmachine is a javascriptless-by-default anonymous textboard engine with various text effects.  

| markup |   effect    |
|--------|-------------|
|   ^^   | 3text       |
|   `    | code        |
|   *    | italic      |
|   **   | bold        |
|   $    | rainbowtext |
|   $$   | shaketext   |
|   %%   | spoiler     |
|   !!   | glowtext    |
|   ==   | redtext     |
|   >    | greentext   |
|   <    | bluetext    |
|  [[]]  | button      |

---

# Running it locally with Docker

Everything runs in containers. You do not need Crystal, Postgres, Node or
ImageMagick installed on your machine — only Docker with the Compose plugin.

## First run

```sh
make build-dev     # docker-compose build -- builds the image, installs shards
make dev           # docker-compose up    -- starts the app and the database
```

Or without make:

```sh
docker compose build
docker compose up
```

The first build takes a while: it pulls `amberframework/amber:0.36.0`,
installs ImageMagick, and runs `shards install`. Later builds are cached
unless `shard.yml` or the `Dockerfile` changes.

Then open **http://localhost:3000**.

## What happens on boot

`src/ratmachine.cr` runs three things before the server starts, so a fresh
checkout needs no setup steps:

1. **`initialize_database`** — creates the database named in `DATABASE_URL` if
   it does not exist, then runs every migration in `db/migrations/` through
   micrate. A broken migration takes down the app, not just the suite.
2. **`initialize_captcha_directory`** — `mkdir -p public/dist/images/captcha`,
   where generated CAPTCHA PNGs are written. It is gitignored.
3. **The moderator wizard**, but only when the `users` table is empty. Outside
   production it does not prompt: it reads `RATMACHINE_MOD_USERNAME` and
   `RATMACHINE_MOD_PASSWORD` from the environment and prints what it created.
   In production it prompts on stdin instead, which is why the compose file
   sets `stdin_open` and `tty`.

## What you get

| | where | notes |
|---|---|---|
| The board | http://localhost:3000 | |
| Moderator panel | http://localhost:3000/mod | |
| Postgres | `localhost:5433` | mapped from 5432 in the container |
| App container | `ratmachine-ratmachine-1` | |
| Database container | `ratmachine-db-1` | |

**The development moderator login is `wojak` / `tfwnogf`.** It is set in
`docker-compose.yml`, in the repository, in plain text. It exists so a fresh
checkout has a way into `/mod`. Never reuse that password anywhere real, and
never point this compose file at a public host.

## Environment variables

All set in `docker-compose.yml`:

| variable | value here | what it does |
|---|---|---|
| `DATABASE_URL` | `postgres://admin:password@db:5432/ratmachine_development` | overrides the YAML config. See the warning under *Running the specs*. |
| `RATMACHINE_MOD_USERNAME` | `wojak` | first-run moderator, non-production only |
| `RATMACHINE_MOD_PASSWORD` | `tfwnogf` | as above |
| `RATMACHINE_CAPTCHA_ENABLED` | `"true"` | on by default in production, off elsewhere; this forces it on in development. Any unrecognised value means **off**. |

Two more are read but not set here: `RATMACHINE_TRIPCODE_SECRET` and
`AMBER_ENV` (which the base image sets to `development`).

## Editing code

`amber watch` recompiles on change and restarts the server. Watch the logs to
know when a rebuild finished:

```sh
docker compose logs -f ratmachine
```

Three things worth knowing before you lose an hour to one of them:

- **`.ecr` templates are not watched.** `amber watch` watches `config/**/*.cr`,
  `src/**/*.cr` and `src/views/**/*.slang`. Editing a view does nothing —
  `touch` any `.cr` file to force a rebuild.
- **A compile error may take the container down.** Usually the watcher logs
  the error and keeps serving the previously built binary — so the site looks
  fine while your change is not running, which is its own trap. Sometimes it
  ends with `Compile time errors detected, exiting...` and stops. Either way
  the log tells you; `docker compose up -d` brings it back.
- **Crystal compilation is memory-hungry** and the container has been
  OOM-killed (exit 137) mid-rebuild. If containers vanish, run
  `docker compose ps -a` before assuming your change broke something.

The repository is bind-mounted at `/app`, so edits on the host are visible
immediately. `/app/lib` is a **named volume** instead, so the shards installed
during the image build are not hidden by that bind mount.

That volume is also a trap. It is populated once, when it is first created,
and never again — so rebuilding the image after adding a dependency to
`shard.yml` does **not** update `/app/lib`. Install it in the running
container:

```sh
docker compose exec ratmachine shards install
```

or drop the volume and let the next boot repopulate it
(`docker compose down -v`, which also destroys the database).

## Stylesheets

Webpack runs inside the container as part of `amber watch`, so editing
`src/assets/stylesheets/*.css` rebuilds `public/dist/*.bundle.css`
automatically. To force one:

```sh
docker compose exec ratmachine npm run build
```

**Do not run `npm run build` on the host.** The container's watcher owns
`public/dist` as root, and a host build fails with `EACCES`.

## A shell, and the database

```sh
docker compose exec ratmachine sh                 # shell in the app container
docker compose exec db psql -U admin -d ratmachine_development
```

Useful queries while developing:

```sh
# every board (a board is a post with no parent)
docker compose exec -T db psql -U admin -d ratmachine_development \
  -c "SELECT id, message FROM posts WHERE parent IS NULL;"

# how many posts a board holds, against the 254 purge threshold
docker compose exec -T db psql -U admin -d ratmachine_development \
  -c "SELECT board, COUNT(*) FROM posts WHERE parent IS NOT NULL GROUP BY board;"
```

## Running the specs

The test database is **not** created automatically. Once, ever:

```sh
docker compose exec -T db psql -U admin -d postgres -c "CREATE DATABASE ratmachine_test;"
```

Then:

```sh
docker compose exec ratmachine sh -c 'cd /app && AMBER_ENV=test crystal spec'
```

> **The suite truncates tables.** It is wired to truncate `ratmachine_test`,
> and `spec/spec_helper.cr` deletes `DATABASE_URL` *before* the config loads so
> the compose value cannot drag it onto the development database. That single
> line is the only thing standing between a spec run and every post you have.
> **Read [`docs/testing.md`](docs/testing.md) before touching `spec_helper.cr`,
> `config/settings.cr` or the compose environment** — it explains the failure
> and gives a canary check for verifying the guard still holds.

## Turning things off and on

```sh
docker compose stop                  # stop, keep everything
docker compose down                  # stop and remove containers, keep volumes
docker compose down -v               # ALSO DESTROYS the db and shards volumes
```

`down -v` deletes every post, board, ban and moderator. The next boot starts
from an empty database and recreates the moderator from the environment.

To rebuild after changing the `Dockerfile` or `shard.yml`:

```sh
docker compose build --no-cache ratmachine
```

## CAPTCHA

On in this environment, which means every form render shells out to
ImageMagick (`convert`, installed in the image) and writes a PNG. If page
loads feel slow, or you want to post without solving anything, set
`RATMACHINE_CAPTCHA_ENABLED: "false"` in `docker-compose.yml` and restart.

See [`docs/captcha.md`](docs/captcha.md) for how it works and what it does not
protect.

## Live mode

*Only on the `live-prototype` branch; `master` has none.*

Off by default, and off means the page ships no JavaScript at all. Turn it on
with the **LIVE** button in the top right (in the nav bar on a phone), or by
visiting `/live/on`. Posts then appear without a reload, fading in as they
arrive. See [`docs/live-mode.md`](docs/live-mode.md).

---

# Building a release

```sh
make build          # npm run build, then shards build --release
bin/ratmachine
```

On first startup the database is created and migrated automatically, and you
will be prompted for a moderator username and password for `/mod`.
