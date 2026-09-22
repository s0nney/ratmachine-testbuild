# Testing

```sh
docker compose exec ratmachine sh -c 'cd /app && AMBER_ENV=test crystal spec'
```

Current state: **26 examples, 0 failures.**

---

## Read this before running the suite

The specs truncate tables. They are supposed to truncate `ratmachine_test`, and
after the fix described below they do — but the wiring that keeps them off the
development database is easy to undo by accident, and when it breaks there is
no warning. It silently deletes every post.

### What went wrong

`config/environments/test.yml:24` points the suite at `ratmachine_test`. But
`config/settings.cr:91` lets an environment variable override the YAML:

```crystal
settings.database_url = ENV["DATABASE_URL"] if ENV["DATABASE_URL"]?
```

`docker-compose.yml` sets `DATABASE_URL` to **ratmachine_development** for the
app container. So `AMBER_ENV=test crystal spec` loaded `test.yml`, then threw
its database away and connected to development instead. `ratmachine_test` had
never even been created.

Combined with the truncation hooks below, every spec run wiped the development
board.

### The fix

`spec/spec_helper.cr:8` deletes the variable *before* the config is loaded, so
the YAML wins:

```crystal
ENV["AMBER_ENV"] ||= "test"
ENV.delete("DATABASE_URL")
require "../config/*"
```

Order matters. Crystal runs top-level code in require order, so the `delete`
must sit above `require "../config/*"` — move it below and the override comes
back.

### Verifying it still holds

Cheapest possible check, any time you touch `spec_helper.cr`, `settings.cr` or
the compose environment:

```sh
# leave a canary in development
docker compose exec -T db psql -U admin -d ratmachine_development \
  -c "INSERT INTO posts (message, created_at, updated_at) VALUES ('canary', NOW(), NOW());"

docker compose exec ratmachine sh -c 'cd /app && AMBER_ENV=test crystal spec'

# it must still be there
docker compose exec -T db psql -U admin -d ratmachine_development \
  -c "SELECT message FROM posts WHERE message = 'canary';"
```

If the canary is gone, the suite is on the wrong database. Stop and fix it
before running anything else.

---

## The truncation hooks

Three spec files exist solely to truncate a table:

| File | Hook | `it` blocks |
|---|---|---|
| `spec/models/post_spec.cr` | `Post.clear` | **0** |
| `spec/models/captcha_spec.cr` | `Captcha.clear` | **0** |
| `spec/models/filter_spec.cr` | `Filter.clear` | **0** |

They contribute **no tests at all** — they are scaffolding for specs that were
never written. They only delete.

Worse, they use `Spec.before_each`, which in Crystal is a **global** hook, not
one scoped to the enclosing `describe`. Being inside `describe Post do ... end`
does not limit it. All three run before *every* example in the suite, so the
13 examples trigger 39 truncations.

That is why these files are dangerous out of proportion to their size. If you
ever want the suite to stop touching the database entirely, deleting these
three files costs nothing — there is no coverage to lose.

---

## What the suite actually covers

| File | Examples | Subject |
|---|---|---|
| `spec/core/usecase/check_digits_spec.cr` | 5 | Dubs/trips detection |
| `spec/helpers/captcha_spec.cr` | 8 | `CaptchaHelper.enabled?` and the disabled form |
| `spec/models/overboard_spec.cr` | 3 | Combined threads, 30-thread limit, and nested-reply activity |
| `spec/controllers/guard_spec.cr` | 3 | Anonymous, malformed, and authenticated moderator sessions |
| `spec/controllers/theme_spec.cr` | 4 | Same-page theme redirects and invalid destination handling |
| `spec/helpers/poster_id_spec.cr` | 8 | Poster ID shape, per-address/board/day scope, midnight rotation, keying |

Other areas remain untested: most posting behavior, the formatter, filters, bans, boards,
backlinks, the per-board post cap, and most controller behavior.

The original digit and CAPTCHA examples do not touch the database. The new
overboard specs create posts in the isolated test database and use the existing
clearing hooks. Always run with `AMBER_ENV=test`.

---

## The suite did not compile at all

Before this was fixed, `crystal spec` failed on:

```
spec/spec_helper.cr:15: undefined constant Logger
```

`Logger` was removed in Crystal 0.35; this project runs 0.36.1. The line is now
`Log.setup("granite", :none)` (`spec/spec_helper.cr:22`).

This is worth knowing for an unpleasant reason: because the suite had never
compiled, `Post.clear` had never run, so the database hazard above was latent
and invisible. Fixing the compile error is what armed it.

---

## Setup

`ratmachine_test` is not created automatically — `initialize_database` only
creates the database named in the running application's own URL. Create it once:

```sh
docker compose exec -T db psql -U admin -d postgres -c "CREATE DATABASE ratmachine_test;"
```

`spec_helper.cr:19` then runs `Micrate::Cli.run_up` against it on every spec
run, so migrations are applied automatically and the test database stays in
step with `db/migrations/`.

---

## Adding specs

- Put database-free unit specs under `spec/core/` or `spec/helpers/` — they run
  fast and cannot damage anything.
- `spec/helpers/captcha_spec.cr` is a reasonable model for specs that need to
  manipulate `ENV`: it saves, sets, and restores in an `ensure` block so one
  example cannot leak state into the next.
- If you write specs that do need the database, prefer `before_each` (scoped)
  over `Spec.before_each` (global), so your setup doesn't run before unrelated
  examples.
- Controller/integration specs would need `garnet_spec`, which is commented out
  at `spec/spec_helper.cr:12` and is not in `shard.yml`.

## Gotchas

- **`amber watch` does not watch `.ecr` files.** It watches `./config/**/*.cr`,
  `./src/**/*.cr` and `./src/views/**/*.slang`. Editing a view template does not
  trigger a rebuild — `touch` a `.cr` file to force one.
- **Crystal compilation is memory-hungry.** The app container was OOM-killed
  (exit 137) mid-session during a rebuild. If containers disappear mid-work,
  check `docker compose ps -a` before assuming your change broke something.
- **Migrations run on app boot**, from `initialize_database` in
  `src/ratmachine.cr`, and separately on every spec run against the test
  database. A broken migration takes down the app, not just the suite.
