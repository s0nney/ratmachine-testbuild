# The captcha

A homegrown captcha: six random lowercase letters, distorted by ImageMagick
into a PNG, stored as a row and validated once. There is no third-party
service, no JavaScript, and no audio or accessible alternative.

It guards two forms — the posting form and the mod login — and it is the only
thing standing between a client and either of them, since the application has
no rate limiting of any kind. See [`rate-limiting.md`](rate-limiting.md).

Documented 2026-09-22 against `1b432a6`.

---

## The pieces

| file | what it does |
|---|---|
| `src/models/captcha.cr` | Generation, image rendering, validation, expiry |
| `src/helpers/captcha/captcha.cr` | Creates the image directory at boot |
| `src/helpers/captcha/captcha/form_helper.cr` | `enabled?` and the rendered form fragment |
| `src/core/usecase/check_captcha.cr` | Wraps validation with a status message |
| `db/migrations/20181116213455183_create_captcha.sql` | The table |
| `spec/helpers/captcha_spec.cr` | Covers `enabled?` and the disabled form |

The table is four columns:

```sql
CREATE TABLE captchas (
  id BIGSERIAL PRIMARY KEY,
  value TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

The answer is stored in plaintext. Nothing else about the captcha is recorded —
not who it was issued to, not which form, not whether it was ever attempted.

---

## On or off

`CaptchaHelper.enabled?`:

```crystal
TRUTHY = %w(1 true yes on)

def self.enabled?
  if setting = ENV["RATMACHINE_CAPTCHA_ENABLED"]?
    TRUTHY.includes?(setting.downcase.strip)
  else
    ENV["AMBER_ENV"]? == "production"
  end
end
```

**Default: on in production, off everywhere else.** The reason is cost —
development would otherwise shell out to ImageMagick on every form render,
which is every board page view.

`RATMACHINE_CAPTCHA_ENABLED` overrides in both directions and is checked first,
so production can be turned off as easily as development can be turned on.
An unrecognised value is **off**, including in production —
`RATMACHINE_CAPTCHA_ENABLED=banana` silently disables the captcha on a live
site. `docker-compose.yml` sets it to `"false"` explicitly, with a comment
saying to flip it to exercise the captcha locally.

When disabled, `captcha_form` returns `""` and both controllers' checks return
`true` before touching the database, so no row is written and no image is
rendered.

---

## Generating one

`Captcha.generate` runs on every render of a form that carries a captcha.

```crystal
def self.generate_captcha_string(length)
  string = ""
  length.times do
    string += ('a'.ord + Random.rand(26)).chr
  end
  string
end
```

Six lowercase letters, `a`–`z`, from `Random.rand` — the default PRNG, not
`Random::Secure`. About 309 million combinations. Blind guessing is not the
threat model here; OCR is, and the alphabet being letters-only and lowercase
makes it an easier target than a mixed-case alphanumeric one would be.

The row is created first so its `id` can name the file, then the image:

```crystal
pointsize  = 32 + Random.rand(16)          # 32..47
amplitude  = 2 + Random.rand(4)            # 2..5
wavelength = 30 + Random.rand(40)          # 30..69
swirl      = (Random.rand(2) == 0 ? -1 : 1) * (15 + Random.rand(25))

Process.run("sh", ["-c",
  "convert -background transparent -fill black -font DejaVu-Sans " \
  "-pointsize #{pointsize} -size 192x64 -gravity Center " \
  "label:#{value} -wave #{amplitude}x#{wavelength} -swirl #{swirl} " \
  "png:- 2>&1 > public/dist/images/captcha/#{id}.png"])
```

Four randomised parameters, all bounded so the glyphs stay inside the 192×64
canvas. `-swirl` picks a direction as well as a magnitude.

**`-swirl` rather than `-implode`, deliberately.** On a transparent canvas
`-implode` fills everything outside its circle from the background, which
inverts the alpha and leaves the glyphs as holes punched in an opaque blob.
`-swirl` distorts just as well without touching transparency. The comment in
the source says so; it is the kind of thing that gets "simplified" back.

**The redirection looks wrong and is not.** `2>&1 > file` binds stderr to the
*current* stdout — the application's own output — and only then points stdout
at the file. So the PNG lands cleanly and ImageMagick's errors go to the
container log. Rewriting it to the more familiar `> file 2>&1` would send error
text into the PNG and corrupt it.

**No injection surface**, though it reads like one. The only interpolations are
`value`, which is `a`–`z` by construction, and `id`, an integer from the
database. Neither can carry shell metacharacters. Worth keeping in mind if the
alphabet ever changes.

### Dependencies this creates

- **ImageMagick must be installed.** `Dockerfile` does
  `apt-get install -y --no-install-recommends imagemagick`. Without it every
  captcha is a zero-byte PNG and no error reaches the user.
- **The `DejaVu-Sans` font must resolve** under that name. It is a
  Debian-ism; on another base image the name differs and `convert` fails.
- **`sh` is spawned per captcha** — one process per form render.
- **A writable `public/dist/images/captcha/`.** `initialize_captcha_directory`
  runs `FileUtils.mkdir_p` at boot from `src/ratmachine.cr`, before the server
  starts. The directory is gitignored (`.gitignore:16`), and the blueprint
  excludes the images deliberately.

---

## The rendered form

```crystal
def self.captcha_form()
  return "" unless enabled?
  new_captcha = Captcha.generate()
  <div class="captcha_form">
    <img src="/dist/images/captcha/<id>.png" alt="captcha">
    <input type="hidden" name="captcha_id" value="<id>">
    <input type="text" name="captcha_value" placeholder="captcha" autocomplete="off">
  </div>
end
```

The id travels in a hidden field, so the server needs no session state to know
which captcha it is checking. `autocomplete="off"` keeps the browser from
offering previous answers.

The image is served as an ordinary static file by Amber's static pipeline —
**no authentication, no referer check**. Anyone who knows an id can fetch the
PNG. Ids are sequential `BIGSERIAL`, so they are trivially guessable, though
fetching someone else's image gains nothing: you would still have to read it.

`alt="captcha"` is the whole accessibility story. There is no audio
alternative, no "can't read this" refresh link, and no way past it for a
screen-reader user. Reloading the page is the only way to get a different
image.

Called from exactly two places:

- `IndexController` — inside the posting form, after the message textarea
- `ModController#render_login_form` — after the password field

---

## Validating

`PostController#check_captcha` and `ModController#captcha_valid?` both route
through the same use case:

```crystal
unless CAPTCHA_GATEWAY.is_valid?(captcha_id, captcha_value)
  return { valid: false, status: "Incorrect or expired CAPTCHA" }
end
```

and the model:

```crystal
def self.is_valid?(id, value, destroy = true)
  destroy_old
  found_captcha = Captcha.find(id)
  return false if found_captcha.nil?
  found_captcha_value = found_captcha.value
  found_captcha.delete() if destroy
  found_captcha_value == value
end
```

Four properties worth naming:

**Single-use, including on failure.** The delete happens *before* the
comparison, so a wrong answer burns the captcha exactly as a right one does.
One image cannot be attacked repeatedly. This is the only thing that makes
repeated attempts cost anything — and it is a consequence of statement
ordering, not a designed lockout. Anyone tidying this method must keep the
delete above the comparison.

**A missing row is indistinguishable from a wrong answer.** Both return
`false`, and the message says "Incorrect or expired" without saying which.

**The comparison is `==` on a plaintext string.** Not constant-time, but the
value is public in the image anyway, so there is nothing to leak.

**`destroy: true` is a default parameter** that nothing ever overrides. Both
call sites take it. The `false` branch is dead.

### Expiry

```crystal
def self.destroy_old()
  Captcha.where(:created_at, :lt, Time.utc - 5.minutes).each do |captcha|
    captcha.delete()
  end
end
```

Five minutes. There is **no sweeper, no cron and no background fiber** — it
runs lazily, on every `generate` and every `is_valid?`. Consequences:

- A quiet site never cleans up. Rows and PNGs from the last burst sit there
  until somebody next loads a form.
- Cleanup cost scales with the backlog and lands on whichever unlucky request
  triggers it, one `DELETE` and one `File.delete` per row.
- `Captcha#delete` is overridden to unlink the PNG before destroying the row,
  with the `File.delete` wrapped in a bare `rescue`, so a missing file does not
  break the sweep — and a failure to unlink is silent.

Five minutes is also the window in which a bot can bank pre-solved captchas.

---

## Styling

`.captcha_form` is laid out only inside the handheld breakpoint in `main.css`:
`order: 3`, full-width flex column, image above the answer field, both with
the 2px inset bevel and `--theme-field` backing. On desktop it inherits the
form's ordinary flow.

**Themes must back the image.** The PNG is black glyphs on transparent, so a
dark palette renders it as black-on-black. `cyb.css` carries one of its only
two real rules for exactly this:

```css
/* CAPTCHA images contain black glyphs and need a light backing. */
.captcha_form img { background-color: #dcffd5; }
```

`main.css` gives it `--theme-field`, which is light. Any new theme has to
handle this, and the theme preview page cannot show it — captchas are
generated per request and the preview has no server. The blueprint's
`themes-howto.md` calls it out under "What the preview cannot tell you".

---

## Test coverage

`spec/helpers/captcha_spec.cr` covers `enabled?` thoroughly — every
environment/flag combination, truthy values, and that an unrecognised value is
off — plus that `captcha_form` renders `""` when disabled.

**Nothing covers generation or validation.** `spec/models/captcha_spec.cr` is a
`describe Captcha` block containing only a `before_each` that calls
`Captcha.clear`, and no examples at all. So `is_valid?`'s
delete-before-compare, the five-minute expiry, and the PNG unlink are all
untested — which is unfortunate, because the delete ordering is the load-
bearing security property of the whole system.

Testing generation means either ImageMagick in the test environment or
extracting the image rendering behind a seam. Validation and expiry need
neither and could be tested today.

---

## Known weaknesses, collected

Most of these are elaborated in [`rate-limiting.md`](rate-limiting.md).

1. **Not bound to anything.** A captcha id is tied to no session, IP, form or
   endpoint. One minted on the board form is accepted at the mod login.
2. **Unbounded pool.** Every board page view mints one. A script can bank
   hundreds and spend them inside the five-minute window.
3. **The mod login never consumes it on a wrong password.**
   `user.nil? || !captcha_valid?` short-circuits, so a password-guessing loop
   can reuse a single captcha indefinitely.
4. **Free to fail.** No counter, no lockout, no backoff. A wrong answer costs
   one HTTP round-trip.
5. **A process spawn per page view.** The cheapest way to load this server is
   to request board pages in a loop and never post.
6. **`Random` rather than `Random::Secure`** for the answer.
7. **Inaccessible.** No audio, no alternative, no refresh link.
8. **Weak alphabet.** Six lowercase letters is an easy OCR target.

---

## If this is to be rebuilt

Keep: the hidden-id design, which needs no session state; the lazy expiry,
which needs no scheduler; the on-in-production-only default; the transparent
canvas with a themed backing.

Change: bind the captcha to what it was issued for, make failures cost
something, and either drop the homegrown renderer for a library that does not
need a subprocess, or cache a pool of pre-rendered images and hand them out
rather than rendering one per page view. The last of those alone removes the
largest unauthenticated cost in the application.
