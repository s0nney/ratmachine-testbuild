# Live mode

Posts appear without a reload, fading in as they arrive. Off by default, and
"off" means the page ships no JavaScript at all — not an inert script, none.

**This is a prototype, on the `live-prototype` branch.** `master` has no live
mode. Abandoning it is `git checkout master`; nothing here writes a migration
or changes a table.

Written 2026-09-24 against `30f4239`.

---

## The shape of it

```
Post.reply / Post#delete
        │  appends
        ▼
   Live::LOG          in memory, per board, 200 events, sequence-numbered
        │  read by
        ▼
  LiveController#feed          one held SSE connection per viewer
        │  text/event-stream   server holds the cursor AND the thread list
        ▼
   public/js/live.js           97 lines, no framework, no build step
        │
        ▼
   DOM: insert / replace / remove / reorder, arrivals get .post_arriving
```

Five files do the work: `src/core/live/event_log.cr` (66 lines),
`src/controllers/live_controller.cr` (168), `public/js/live.js` (97), the live
mode helpers on `ApplicationController`, and one CSS block in `main.css`.

---

## The toggle

A cookie, `live_mode`, and **the cookie is the only thing that decides**.
`ApplicationController#live_enabled?` is `cookies["live_mode"] == "on"` —
anything else, including an absent cookie or a misspelt value, is off.

`GET /live/:state` sets it and redirects back via `?return_to=`, so **turning
live mode on or off needs no JavaScript**. It is an ordinary link. The return
path is validated by `ThemeController.return_path`, reused rather than
reimplemented: the cookie toggle and the theme toggle have the same
open-redirect surface and should not drift apart.

`state` is `"on"` or, for any other value, `"off"`. The allow-list is
inherent rather than written out, because there are only two states.

### Where the button is

Rendered twice, in two places, with CSS showing whichever fits:

- **Desktop:** fixed to the top right at `right: 92px`, immediately left of the
  theme switcher, which is 44px wide at `right: 40px`. Same hanging-tab
  furniture as the switcher — outset bevel, bottom corners rounded — going
  inset when live mode is on, the way the theme drawer handle does when open.
- **Handheld:** inside `.mobile_navigation`, centred. It has to be
  `position: absolute` there: the bar is `justify-content: space-between` and
  the Overboard tab is much wider than the jump arrows, so as a flex item it
  lands about 50px left of centre. Absolute positioning centres it against the
  bar rather than against its neighbours.

A dot on the left of the label is grey when off and green when on. That dot
and the inset border are the only state the button carries.

### What "off" ships

Nothing. Verified by measurement, not assumption — with the cookie unset a
board page makes **no requests** for `live.js` or `/feed`:

| | off (default) | on |
|---|---|---|
| `<script>` | absent | `/js/live.js` |
| `data-live-scope` on `<body>` | absent | board slug, or `""` for the overboard |
| network | nothing | one held `/feed` connection |

`spec/controllers/live_mode_spec.cr` asserts those **absences**. That is the
only thing keeping them true: a stray attribute added to the wrong branch is
invisible in a browser and would otherwise go unnoticed indefinitely. Eight
examples, including that an unrecognised cookie value is not treated as on.

The one part of live mode present either way is two CSS rules — the
`post-arriving` keyframes and the class that uses them. Nothing applies that
class without `live.js`, and a second stylesheet for two rules was not worth
the request.

---

## The event log

`Live::LOG`, a `Live::EventLog`, in memory and single process.

Per board: a capped ring of 200 sequence-numbered events, each a
`Live::Event(seq, kind, post_id, thread_id)`. `thread_id` is the **top-level
post the change belongs to** — the unit a client re-renders.

Four kinds, appended by the model rather than by a controller, so anything
that creates or destroys a post is recorded however it got there:

| kind | appended by | when |
|---|---|---|
| `:created` | `Post.reply` | every post, top-level or reply |
| `:deleted` | `Post#delete` | the purge, and moderator deletion |
| `:promoted` | `Post#delete` | a child re-homed by `orphan_children` when its parent was a thread |
| `:reload` | `Post#move_to_board` | on both the old and new board |

`since(board_id, seq)` returns the events after `seq`, or the symbol
`:reload` when the caller is too far behind to be caught up — better than
letting a client drift silently out of step with the database. An unknown
board is empty rather than a reload: a board nobody has posted to since the
server started has no history to have missed.

**Working out `thread_id` is the subtle part.** `Post.reply` climbs the
ancestor chain anyway to update `last_reply`, so the walk captures the thread
as it goes. Two cases fall outside that walk and are handled explicitly: a
top-level post is its own thread, and a **saged** reply skips the mutating
walk entirely (it must not bump its ancestors) but still belongs to one, so
`Post.thread_id_for` climbs read-only. Getting this wrong means a reply that
never appears.

---

## The stream

`GET /feed/:board`, or `GET /feed` for the overboard. `text/event-stream`,
held open, `Cache-Control: no-store`, and `X-Accel-Buffering: no` — nginx
buffers proxied responses by default, which would hold every event until the
connection closed. That is, break this entirely, and silently.

Amber 0.36 has no SSE helper, but it does not need one: write to `response`,
call `flush`, and it streams as chunked. This was spiked before anything was
built around it, because it was the one assumption that could have sunk the
design.

### The cursor lives on the server

This is the whole reason to prefer SSE over polling here.

A held connection knows what it is watching and what the page is showing, so
it keeps both itself:

- `cursors` — a sequence number per watched board, starting at
  `current_seq` at connect time, so the stream reports only what happens from
  then on.
- `known` — the thread ids the rendered page contains, so the stream can tell
  an **arrival** from an **update** without asking the browser.

The browser therefore sends nothing after the initial GET. The earlier polling
experiment needed a hidden cursor element, a `threads=` parameter and a random
process epoch to detect restarts, threaded through every response. None of
that exists here.

`Live::EPOCH` survives in `event_log.cr` and is now **unused** — it belonged
to the polling design. Left in place rather than removed because the polling
transport is the documented fallback if held connections turn out to be
unworkable in a real deployment.

### A tick

Every `TICK` (0.4s) the fiber asks the log what changed. Nothing did, almost
always, and that costs one mutex and one array lookup per watched board — **no
database**. When something did:

1. Any `:reload` event ⇒ send `{"reload":true}`, client reloads.
2. Recompute the visible threads (`Post.get_replies`, or
   `Post.overboard_threads`).
3. Anything `known` that is no longer visible ⇒ **remove**. That covers the
   purge, and a thread pushed off the overboard's 30-item cutoff by somebody
   else's post.
4. Each touched thread still visible ⇒ **replace** if the page has it,
   **insert** if not.
5. Send the whole `order`, so bumped threads re-sort.
6. Send the board stats line.

`MAX_LIFETIME` is 10 minutes, then the connection closes and `EventSource`
reconnects on its own. A forgotten tab does not hold a fiber forever.

---

## The client

97 lines, vanilla, no dependencies. It applies what arrives; it decides
almost nothing.

**Arrivals are found by difference, not by trust.** Before applying a batch it
snapshots every post id on the page, and afterwards animates whatever was not
there before. So when a reply arrives and the server re-renders the whole
thread it sits in, **only the reply fades** — the surrounding thread does not
flash. A rule that says "animate what the server called an insert" would get
that wrong.

`.post_arriving` runs 420ms of opacity and a 5px rise, then removes itself on
`animationend` so a later re-render of the same thread does not replay it.
`prefers-reduced-motion: reduce` gets the post immediately, with no movement.

Ordering walks the `order` array from `#board_top`, moving nodes with
`after()`. Moves rather than rebuilds: `innerHTML` would silently re-open
every `<details>` the reader had collapsed.

---

## Scope

| page | live | why |
|---|---|---|
| `/b/:slug` | yes | its own board's stream |
| `/` overboard | yes | every board, `data-live-scope=""` |
| `/b/:slug/:id` | yes | see below |
| `/mod/*` | no | different layout, no `live_runtime`, nothing to update |

A reply page is **not** a subtree view — it renders the same board as a board
page, with `selected_post` on one post — so the same fragments fit it. The one
thing it needs is which post is selected, or a re-render drops the highlight
the reader is looking at. That travels as `data-live-reply` on the body and
`?reply=` on the feed URL; an unparseable value is simply no selection.

---

## What it costs, honestly

- **A fiber and a connection per viewer**, for up to ten minutes. Nothing caps
  the total. Crystal fibers are cheap, but this is a single process.
- **A database query per tick that has changes** — the visible thread list is
  recomputed wholesale rather than diffed incrementally. Fine for one board,
  wasteful for a busy site.
- **HTTP/1.1 caps around six connections per host**, and an SSE stream holds
  one permanently, so a reader with several tabs can starve themselves.
  HTTP/2 makes it a non-issue, which turns TLS in production into a
  requirement rather than a nicety.
- **Anything that buffers responses breaks it**, which is what the
  `X-Accel-Buffering` header is for.
- **A small race at connect.** The cursor starts at the sequence current when
  the *stream* opens, not when the *page* rendered. An event landing in that
  gap is missed until the next one arrives. Acceptable for a prototype;
  a real fix embeds the render-time sequence in the page and passes it on
  connect.
- **Single process, in memory.** Two application instances would each see half
  the events and neither would report it. `Live::EventLog` is the seam if that
  ever changes.

---

## What was tried and dropped

- **An identity rail** listing the poster IDs of everyone reading a board was
  built and removed before shipping, along with a presence store. It made
  lurking visible, which is a product decision rather than a technical one,
  and it was cut.
- **HTMX** was the obvious choice and was deliberately not used here, to keep
  the client dependency-free.
- **Polling** (`hx-trigger="every 3s"`) was the first implementation, forced by
  Amber having no SSE helper. It works, and remains the fallback if held
  connections prove impractical — but it needs the client-side cursor
  machinery that SSE makes unnecessary.
- **Date grouping**, filing threads under collapsible "Today — Thursday,
  September 24, 2026" headings like a browser history sidebar, was built on
  top of this and reverted. It is in the branch history at `64f6be6` and
  `717d595` if it is ever wanted.
