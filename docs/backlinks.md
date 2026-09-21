# Mobile backlinks

4chan-style backlinks, used only by the handheld layout. They exist so that
mobile can present threads **flat** instead of nested, without losing the
reply relationships that nesting normally conveys.

Everything here is JavaScript-free, in keeping with the project's philosophy.

---

## Why

Nesting works on a wide screen but degrades badly on a narrow one: every level
of reply eats horizontal space, and a deep thread quickly becomes unreadable.

So the two views diverge on purpose:

| | Desktop | Mobile |
|---|---|---|
| Thread shape | Nested `<details>` | Flat stream |
| Relationships shown by | Indentation / containment | Backlinks (`>>N`) |
| Collapse a subtree | Yes, via `<details>` | Collapses descendants too |
| Backlinks visible | No | Yes |

The desktop board is unchanged by this feature.

## The core design decision

**The DOM stays nested. Mobile flattens it visually, with CSS.**

The obvious implementation — render a flat list of posts for everyone and
rebuild the tree from `parent` ids — was rejected. The nesting is not
decorative: `<details class="post">` nested inside another is what lets a
desktop reader collapse a parent and hide its entire subtree. Emitting flat
markup would have silently removed that.

Instead, the handheld media query reduces `.post` to a bare wrapper and moves
the card chrome onto the `.post_header` + `.post_content` pair:

```css
.post          { margin: 0; padding: 0; border: none; background: none; }
.post .post    { margin-left: 0; }
.post_header   { border: 2px ridge #8c53b3; border-bottom: none; ... }
.post_content  { border: 2px ridge #8c53b3; border-top: none; margin-bottom: 8px; ... }
```

With no indent and no enclosing box, a depth-5 reply renders identically to a
top-level post. The nesting still exists in the document; it simply contributes
nothing visually. Posts appear in depth-first order.

---

## Server side

All of this lives in `src/controllers/index_controller.cr`.

### Two helpers

`parent_backlink(post)` — `src/controllers/index_controller.cr:79`

Renders `>>123` pointing at the post being replied to. Returns `""` for a
top-level post. Appended to the post's `<summary>` (header).

`reply_backlinks(replies)` — `src/controllers/index_controller.cr:88`

Renders `>>456 >>789` pointing at the posts that replied to this one, wrapped
in `<div class="backlinks">`. Returns `""` when there are no replies. Appended
inside `.post_content`, after the message `<p>`.

### Changes to `render_thread`

- Each `<details class="post">` gains `id="post-N"` (`:35`), so a backlink's
  `:target` lands on the whole card rather than on a link.
- The outermost wrapper post — which carries no message of its own — gains a
  `root_post` class so mobile can hide its empty header and content.
- Replies are collected **once** into an array and used twice, for the
  backlinks and for the recursion:

  ```crystal
  replies = [] of Post
  Post.get_replies(parent).each { |reply| replies << reply }
  ```

  Granite's `Query::Builder` has no `#to_a`, hence the explicit `each`. This
  adds **no extra database queries** — `get_replies` was already being called
  once per post for the recursion.

### Generated markup

```html
<details class="post" id="post-34" open="true">
  <summary class="post_header">
    <a href="34#reply-34" id="reply-34">Reply</a> 34 2026-09-20 02:56:54 UTC
  </summary>
  <div class="post_content">
    <p class="post_text">the message</p>
    <div class="backlinks">
      <a href="#post-36" class="backlink backlink_reply">&gt;&gt;36</a>
      <a href="#post-35" class="backlink backlink_reply">&gt;&gt;35</a>
    </div>
  </div>
  <details class="post" id="post-35" open="true">
    <summary class="post_header">
      <a href="35#reply-35" id="reply-35">Reply</a> 35 ...
      <a href="#post-34" class="backlink backlink_parent">&gt;&gt;34</a>
    </summary>
    ...
  </details>
</details>
```

### Two anchor schemes, on purpose

| Anchor | On | Used by |
|---|---|---|
| `id="reply-N"` | the `<a>` inside the summary | desktop's existing Reply links |
| `id="post-N"` | the `<details class="post">` | backlinks, and `:target` highlighting |

The original `reply-N` anchors were deliberately left in place. Backlinks
needed their own because `:target` styles the element whose id matches — to
highlight the *post*, the id has to be on the post.

---

## CSS

Three stylesheets are involved.

### 1. `main.css` base (desktop) — `:280`

```css
.backlinks,
.backlink_parent { display: none; }
```

Backlinks are emitted for every post on every viewport, then hidden on desktop.
This keeps one rendering path in the controller. The cost is a small amount of
unused markup in the desktop HTML; the benefit is that the controller does not
have to know which viewport it is rendering for — which, without JavaScript and
without User-Agent sniffing, it cannot.

### 2. `cyb.css`

Cyb imports `main.css` at build time and overrides its theme variables. Both
themes share desktop backlink hiding, mobile flat threads, and target
highlighting. Cyb uses a green-on-black palette; see [Themes](themes.md).

### 3. `main.css` handheld query — `@media (max-width: 768px), (orientation: landscape) and (max-height: 600px)`

Flat presentation at `:369`, backlink styling at `:431`.

```css
.backlinks {
	display: block;
	margin-top: 7px;
	padding-top: 5px;
	border-top: 1px solid rgba(246,179,229,.22);
	font-size: .82em;
}

.backlink_parent { display: inline; }
```

**Link appearance.** `.post_content a` is styled for message quotelinks
(deeppink, italic, overline, text-shadow), which is wrong for backlinks, so
they are overridden at higher specificity:

```css
.post_content a.backlink,
.post_header a.backlink {
	color: #ffcaf2;
	font-weight: bold;
	font-style: normal;
	text-decoration: none;
	text-shadow: none;
}
```

Underline is reserved for interaction. Note the specificity trap: `main.css`
has a global `a:hover { text-decoration: underline }` at (0,1,1), but the rule
above is (0,2,1) and would defeat it — so the interaction rules are written at
(0,3,1) to win it back:

```css
.post_content a.backlink:hover,  .post_header a.backlink:hover,
.post_content a.backlink:focus,  .post_header a.backlink:focus,
.post_content a.backlink:active, .post_header a.backlink:active {
	text-decoration: underline;
}
```

`:active` covers the press on touch; `:focus` covers keyboard navigation.

**Target highlighting.** Following a backlink makes its destination the
`:target`, so the post highlights itself — 4chan's jump-to-post feedback with
no JavaScript:

```css
.post:target > .post_header,
.post:target > .post_content { border-color: #be00ff; }

.post:target > .post_header  { background-color: rgba(190,0,255,.42); }
.post:target > .post_content { background-color: rgba(190,0,255,.2); }
```

The wash is stronger on the header than the body so the message stays readable.
The highlight **persists** until another post is targeted, matching 4chan.

---

## Behaviour

- A reply shows `>>N` in its header, pointing at the post it answers.
- A post with replies shows `>>N >>M` under its message, pointing at them.
- Backlinks are plain text until hovered, focused or pressed.
- Tapping one scrolls to that post and highlights it in `#be00ff`.
- The root wrapper post's backlinks list the top-level posts, but its header
  and content are hidden on mobile, so they are never seen.

## Gotchas

- **`.root_post`** — `render_thread(nil)` produces an outer `<details>` that
  contains every top-level post but has no message. Without hiding it, mobile
  would show an empty card at the top of the board.
- **Anchor scrolling happens inside `.board_container > .post.root_post`**, not the document —
  `body` is `overflow: hidden` in handheld mode and the root post is the scroll
  container, keeping board tabs above the composer. Browsers scroll the nearest scrollable ancestor, so `#post-N`
  works, but keep this in mind if the shell layout ever changes.
- **`orphan_children`** (`src/models/post.cr:46`) sets `parent = nil` on the
  children of a deleted post rather than cascading. Their parent backlink
  correctly disappears on the next render; no dangling link is produced.
- **`>>` is not escaped** in the source string. `>` is valid in HTML text
  content, so this renders correctly, but it is worth knowing if the output is
  ever fed somewhere stricter.

## Files

| File | Change |
|---|---|
| `src/controllers/index_controller.cr` | `post-N` anchors, `root_post` class, single-query reply collection, `parent_backlink`, `reply_backlinks` |
| `src/assets/stylesheets/main.css` | desktop hiding rule; handheld flat layout, backlink styling, `:target` highlight |
| `src/assets/stylesheets/cyb.css` | shared-layout import and terminal palette |

## Verified

- All backlink `href`s resolve to a real anchor on the page — **0 dangling**
  out of 8 anchors across 4 posts.
- Relationships checked against the database: root posts carry no parent
  backlink; replies point at their parent; parents list their replies.
- Desktop base CSS unchanged apart from the hiding rule (3824 → 3865 bytes);
  nesting indent and post borders intact; no handheld rules leak out of the
  media query.
- `:target` appears nowhere outside the media query.
- Replying still works end-to-end (302 + new backlink appears).
- Spec suite: 13 examples, 0 failures.

**Not verified visually.** No browser was available during implementation, so
spacing, the backlink row's weight under each message and the highlight's
intensity have not been seen rendered. They are the most likely things to need
tuning.

## Possible future work

- Fade the `:target` highlight after a moment with `@keyframes` instead of
  leaving it persistent.
- Show the quoted post's text on backlink hover (4chan does this — it needs
  JavaScript, so it is out of scope here).
