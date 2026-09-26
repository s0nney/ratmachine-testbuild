# Boards

Multiple boards, switched with a strip of tabs. A board is a post with no
parent; threads hang off it through the existing `parent` column, so posting to
a board is literally replying to the board post.

JavaScript-free, like the rest of the application.

---

## The model

Three decisions shape everything below:

| Decision | Choice |
|---|---|
| What a board *is* | A `Post` with `parent IS NULL`; its `message` is its name |
| Who creates them | Mods only, from `/mod/board` |
| The 255-post cap | Per board, not site-wide |

```
posts
  id | parent | board | message
  ---+--------+-------+----------
  54 |  NULL  | NULL  | general     <- board
  58 |   54   |  54   | Test        <- thread on /b/general
  60 |   54   |  54   | a test 2
  56 |  NULL  | NULL  | Tech        <- board
  57 |   56   |  56   | hello tech  <- thread on /b/tech
```

Because a board is just a post, `get_replies`, `render_thread`,
`orphan_children` and the reply chain all work unchanged. `render_thread(board)`
renders the board's threads exactly as it previously rendered the whole site.

### The `board` column

`posts.board` is a **denormalised pointer to the root**, added by the migration.
It is not part of the concept — the parent chain is the truth — but without it,
answering "how many posts are on this board?" needs a recursive descent. The
per-board cap has to ask that on every single post, so the pointer is cached.

It is set in one place, `Post.reply`, and never walks the tree: a new post's
parent is either a board itself (so the board is that parent) or already carries
a pointer (so the board is that pointer). See `Post.board_for`
(`src/models/post.cr:29`).

---

## Migration

`db/migrations/20260920000000001_create_boards.sql`

1. `ALTER TABLE posts ADD COLUMN board INT`
2. Creates the default board and re-parents every existing top-level post under
   it, in one statement:

```sql
WITH new_board AS (
  INSERT INTO posts (message, created_at, updated_at)
  VALUES ('general', NOW(), NOW())
  RETURNING id
)
UPDATE posts SET parent = (SELECT id FROM new_board) WHERE parent IS NULL;
```

The `UPDATE` **cannot see the row the CTE inserts** — data-modifying CTEs don't
observe each other's effects — so the new board keeps its `NULL` parent and is
not re-parented under itself. `(SELECT id FROM new_board)` still reads the
`RETURNING` output.

3. Backfills `board` for every non-board post, and indexes it.

---

## Model — `src/models/post.cr`

| Method | Line | Purpose |
|---|---|---|
| `self.boards` | `:19` | Every post with no parent, oldest first |
| `self.board?` | `:23` | Whether a post is a board |
| `self.board_for` | `:29` | The board a new post will belong to, in O(1) |
| `self.reply` | `:37` | Sets `board`, applies the per-board cap |
| `orphan_children` | `:76` | Re-homes a deleted post's children |
| `delete_board` | `:85` | Deletes a board and everything on it |

### The per-board cap

`Post.reply` counts and purges within the new post's board only, so a busy board
can't purge threads out of a quiet one. Boards themselves carry **no** `board`
pointer, which means they can never be selected as a purge candidate — a board
cannot be deleted by activity.

### `orphan_children` — the important one

It used to set `parent = nil` on a deleted post's children. Under this model a
`NULL` parent means *"this is a board"*, so that would have **silently promoted
replies into new boards** — a deleted thread would scatter its replies across
the tab strip.

It now re-homes children onto the deleted post's own parent, preserving the tree.

### Deleting a board

`delete_board` removes the board and every post carrying its id. Re-homing
threads would be meaningless — there is no other board to move them to. Because
every descendant carries the board pointer, one query finds them all regardless
of nesting depth.

---

## Routing

```crystal
get "/b/:board",     IndexController, :index   # config/routes.cr:64
get "/b/:board/:id", IndexController, :index   # :65
get "/:id",          IndexController, :index   # the old catch-all
get "/",             IndexController, :index
```

Board routes **must** precede `/:id`. `/` displays the [overboard](overboard.md);
an unknown board slug falls back to the first board (`resolve_board`, `src/controllers/index_controller.cr:21`).

### Links had to become absolute

The Reply link used to be relative — `href="123"`. From `/b/general` that
resolves to `/b/123`, which matches `/b/:board` with a nonexistent slug and
silently drops the reply target. Reply links are now built from `board_path`
(`:154`), and `PostController#board_path_for` (`:53`) redirects back to the
board the poster was actually on, reading the new post's `board` pointer.

### Slugs

`board_slug` (`src/controllers/application_controller.cr:9`, with a `String`
overload at `:13`) lowercases the name and reduces anything non-alphanumeric to
`-`. `Tech` → `/b/tech`. Creation rejects a name whose slug collides with an
existing board, which is how `Tech` and `tech` are kept from both existing.

---

## Rendering

`render_main` emits the tab strip, then `render_thread(@board, true)`.

The `is_root` flag (`src/controllers/index_controller.cr:74`) marks the board
itself. A root post frames the thread list rather than appearing as a post: no
message, no `post-N` anchor, and its header is hidden — the tab strip replaced
the "Post" button that used to live there.

`post_target` (`:161`) makes the composer's hidden `parent` field default to the
**board's id**, so a top-level post is a reply to the board. No change to
`CreatePost` was needed.

---

## Mod panel

`/mod/board` → `ModController#board` (`:53`), form rendered by
`render_board_form` (`:188`), linked from the panel as "Manage boards".

`BoardController` (`src/controllers/board_controller.cr`) creates
(`:2`) and deletes (`:24`). Creation refuses an empty name, a name with no
alphanumerics, and a duplicate slug. Deletion refuses a non-board id and
**refuses to delete the last board** — the application needs at least one.

---

## Tabs

Desktop rules at `src/assets/stylesheets/main.css:281`, handheld at `:496`.

On desktop, tabs behave as **physical file dividers**: closing one closes
the sheaf of posts filed behind it, and the tab itself stays put.

- Each desktop tab is a `<details open>`; its `<summary>` holds the board link.
- Mobile uses separate navigation-only markup (`div` and links), with no
  arrows or disclosure controls. It lives in `.posting_deck` immediately above
  the composer and shares its outline.
- **Two clipped layers.** `clip-path` would cut a real `border` off the slanted
  edges, so the outer `<details>` paints the border colour with 2px of padding
  and the inner `<summary>` sits inside it painting the face. The active tab's
  outer layer is `#be00ff` only when the board root is the posting target
  (`selected_board`). Selecting an individual reply removes that tab accent.
- **Shape** is a `clip-path: polygon(...)` trapezoid with four extra points per
  shoulder, easing what would be sharp corners at the top of each slant.
- **The arrow** is `::before` on the label — leading edge, `1.15em` — and is the
  only part that toggles. The link carries the padding and `flex: 1 1 auto`, so
  the tab body navigates and only the arrow closes. Closed, it becomes `▸`.
- **Closing the active divider hides the whole root container:**

  ```css
  .board_tabs:has(.board_tab.active_board:not([open])) ~ .post.root_post {
      display: none;
  }
  ```

  The strip precedes the root post as a sibling inside `.board_container`, so
  `:has()` plus `~` reaches it. Closing an *inactive* divider only flips its own
  arrow — it files a section you aren't looking at.
- On handheld the root post scrolls inside the board container. The separate
  posting deck holds both the tabs and composer, joined at the form’s top edge.
- On desktop, closing the root `Post` disclosure hides its posts and shows a
  `.collapsed_board_header` with the last hour's post and poster-identity counts.
  Mobile always displays the root post, even
  after resizing from a collapsed desktop board.
- The composer heading displays the current board name for a new thread;
  replies retain the “Replying to post N” heading.

---

## Gotchas

- **A `NULL` parent now means "board".** Any code that detaches a post must
  re-home it instead, or it becomes a board. `orphan_children` was fixed; check
  anything new that writes `parent`.
- **`:has()` needs Chrome 105+ / Safari 15.4+ / Firefox 121+.** Below that the
  tab still toggles and the arrow still flips, but the sheaf won't collapse —
  it degrades to a no-op rather than breaking.
- **A closed divider reopens on reload.** A CSS toggle sets no cookie, so there
  is nowhere javascriptless to persist it. Persisting would need a route and a
  cookie, the way the theme selector works.
- **Both themes share tab styling and the handheld layout.** Cyb imports the
  main stylesheet and overrides the palette; see [Themes](themes.md).
- **The composer sits outside `.board_container`** (body order: banner, posting_deck,
  board_container), so it survives a closed divider — you can still post with
  the sheaf shut.
- **Board names are free text.** Two different names can reduce to the same
  slug; creation rejects that, but renaming isn't offered, so a bad name means
  delete and recreate — which takes the threads with it.

## Verified

- Migration applied cleanly: default board created, existing top-level posts
  re-parented, `board` backfilled, board itself left with a `NULL` parent.
- Board isolation: a post made on `/b/tech` appears there and **not** on
  `/b/general`.
- Posting to a board redirects back to that board (`/b/tech/59#reply-59`).
- Mod creation works; a duplicate slug (`Tech` then `tech`) is refused.
- Routes `/`, `/b/general`, `/b/tech`, `/mod/login` all 200; an unknown slug
  falls back to the first board.
- Spec suite: 13 examples, 0 failures.

**Not verified visually.** No browser was available, so the tab shape, the
accent wrap and the divider's closed state have not been seen rendered.

## Possible future work

- Per-board settings (description, post cap, captcha on/off) — today the cap is
  a constant and the captcha flag is global.
- Board ordering; the strip is currently oldest-first by creation.
- Rename without delete-and-recreate.

### Connected divider outline

The tab strip paints its joining line behind the tabs. The active tab's opaque
face interrupts that line, joining the tab to the sheet without an internal seam.
On desktop the sheet is the root post container; on handheld it is the composer
immediately below the strip. Both use `--divider-outline`, which becomes the
selection accent only when `.selected_board` is present. The collapsed header is desktop-only; mobile tabs cannot collapse.

### Collapsed board statistics

Updated September 25, 2026: replaces the previous all-retained-posts and
unique-IP totals.

The desktop collapsed strip shows `N posts made per hour with M identities`.
`Post#board_stats` counts retained threads and replies created in the preceding
60 minutes on this board, excluding the board wrapper. Identities are distinct
nonblank stored poster IDs on those posts; daily ID rotation can give the same
poster two identities in a window spanning midnight. These are not online counts.
The server renders the initial counts without JavaScript. Live mode updates them
on posting events and checks every 30 seconds for posts aging out of the window.
Deleted or purged posts no longer contribute.

The window is rolling, not a calendar-hour bucket or an extrapolated rate:
`at - 1.hour < created_at <= at`, with `at` defaulting to the current UTC time.
Posts exactly one hour old and future-dated posts are excluded. Replies count
alongside top-level threads; bumping an old post does not make it count again.
For example, three recent posts carrying the same ID display
`3 posts made per hour with 1 identity`. An empty window displays
`0 posts made per hour with 0 identities`. A missing poster ID still contributes
a post but not an identity. No new table or historical posting ledger is used,
so this is not a count of posts that have already been deleted or purged.

Implementation: `src/models/post.cr` (`board_stats`) and
`src/controllers/index_controller.cr` (`collapsed_board_stats`). The model returns
`{posts: ..., identities: ...}`; the former `unique_ips` key is no longer used.
The Overboard keeps its existing “choose a board to post” message.

The Pinned tab and the Archives board were removed on 2026-09-21; see
[pinned.md](pinned.md). What follows described how Pinned collected posts from
existing boards. It is a special view rather than an additional board record.
