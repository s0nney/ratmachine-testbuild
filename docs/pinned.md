# Pinned posts

The far-right **Pinned** tab opens `/pinned`, a public collection of existing
posts selected by moderators. It is not a normal posting board. On mobile,
Pinned sits at the top right and Overboard at the top left, with inverted tab
shapes hanging from the upper bezel. Both are navigation-only. Ordinary board
tabs stay above the bottom composer.

Moderators can use **Pin / Unpin** beside a post, or **Manage pins** in `/mod`.
The form accepts a post ID. Both mutations require an authenticated moderator
and the standard CSRF token. Boards cannot be pinned, and duplicate pins are
rejected. Visitors see no posting form or pin-management controls.

The collection shows only pinned posts, newest pins first, without automatically
including unpinned replies. Reply links lead to the original board. Parent
backlinks on this view also link to the original board, so no missing local
anchors are emitted when a parent has not been pinned.

`pinned_posts` stores the source post ID, moderator username, and timestamps.
The migration adds a unique foreign key with deletion cascading: explicit post
or board deletion removes its pins. Unpinning leaves the source post intact.
Automatic board pruning skips pinned posts. If all existing posts are pinned,
a board can temporarily exceed its ordinary cap rather than removing a pin.

No JavaScript is used. The app applies the migration at startup.

Testing covers collection membership, unpinning, deletion cleanup, and pruning.
End-to-end checks cover moderator pin/unpin, duplicate rejection, public display,
and anonymous attempts to mutate pins. The shared moderator guard was corrected
to return after redirecting an unauthenticated request; redirect alone did not
stop the protected block from executing. Guard specs cover anonymous, malformed,
and authenticated sessions.
