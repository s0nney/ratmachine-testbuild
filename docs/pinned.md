# Pinned posts — removed

Pinning was removed on 2026-09-21, along with the Archives board. Neither was
finished, and both carried weight through the purge, the tab strip, the mod
panel and the routes.

What went:

- `pinned_posts` table, `PinnedPost` model, `PinController`, `views/pin/`
- routes `/mod/pin`, `/pin/create`, `/pin/delete`, and the `/pinned` collection
- the **Pinned** and **Archives** tabs, and the "system board" concept that
  existed only to give Archives its own tab and make it read-only
- the purge's exemption for pinned posts — **nothing is exempt now**
- the mod panel's "Pin / Unpin" and "Archive" links

What stayed: moving a post to **Spam**, which is an ordinary board that happens
to be a move target (`Post::MOVE_TARGET_SLUGS`).

The drop migration re-homes anything that was filed under Archives onto no
board rather than deleting it; posts are not thrown away here.

If either idea comes back it should be designed fresh. The retention problem
they were both circling — a board is a ~255-post ring buffer, so anything worth
keeping has to escape it somehow — is still open. See `data-model.md`.
