# Posting

Boards retain the original full nested message view, including on reply URLs.
Overboard still shows the latest 30 top-level posts with their replies. There
are no thread previews, separate thread pages, or board pagination.

Titles are optional on top-level posts (up to 120 characters). Empty titles
do not add a heading. Names are optional on all posts (up to 80 characters);
blank names display as Anonymous. Messages retain the 1,024-character limit.

Use `Name#secret` for a tripcode, or `#secret` for an anonymous tripcode. The
secret is converted into a 10-character HMAC-SHA256 code displayed separately
from the name. Only the display name and code are saved. These are site-specific
secure tripcodes, not legacy DES-compatible imageboard tripcodes. Set a stable,
private `RATMACHINE_TRIPCODE_SECRET` in production; otherwise the app uses
Amber's persistent `secret_key_base`. Changing that key changes future codes.
Tripcodes identify a repeated secret; they do not grant moderator privileges.
After a failed submission the display name survives, but the secret must be
re-entered so it is never placed in the redirect URL.

The optional Sage checkbox prevents a reply from updating any ancestor's
activity timestamp or last-reply ID. It does not hide the reply, disable
purging, or prevent a new top-level post from appearing as a new post.

Automatic purging is again enabled on every board at the existing 254-post
threshold, with pinned posts exempt. There are no per-board retention controls.
Migration `20260921000000002` removes the experimental retention setting while
preserving saved titles and adds name, tripcode, and sage columns. Existing post
bodies are preserved. Both themes share the same beveled form styling.
