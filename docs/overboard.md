# Overboard

`/` combines top-level threads from every board. It is a view, not a stored
board, and does not change per-board post limits. The Overboard tab opens this view.

The overboard shows up to 30 threads with their complete reply trees. Threads are
ordered by `updated_at`, then the latest reply ID (or their own ID), then ID.
`Post.reply` records the new reply ID on every ancestor so deep replies bump
their top-level thread. The ID tie-breaker handles timestamps with equal values.

`Post.overboard_threads` fetches only the 30 most recently active threads.
There is no heading or pagination. A `page` query parameter is ignored.

Thread headers link to their originating board. Reply links always open that
board's reply page. Parent backlinks for top-level threads are board links,
rather than links to nonexistent board-post anchors. Nested replies retain
local post anchors. Legacy `/:id` links also resolve the post's actual board.

The overboard has no posting form or CAPTCHA. Its composer area says
“Choose a board to post”; selecting a board opens its normal composer. Desktop
keeps collapsible nested threads; mobile keeps the flat presentation and
navigation-only tabs attached to the composer area. All functionality is
server-rendered and JavaScript-free.

No migration is required. Existing threads initially use their recorded
activity; the corrected ancestor tracking applies to subsequent replies.

Validation: three model specs cover combined-board roots, the 30-thread limit, and deep-reply bumps. The full suite has 16 examples.
