# IP banning

The only per-IP control in the application, and the only one that stops a
specific poster. It is entirely manual: nothing bans anyone automatically, and
there is no rate limit behind it — see [`rate-limiting.md`](rate-limiting.md).

Audited 2026-09-22 against `1b432a6`.

## You never have to look in the database

Every post rendered to a logged-in moderator carries a **Mod** link, built in
`IndexController` alongside the Reply link:

```crystal
href: "/mod?id=#{parent.id}&ip=#{parent.ip_address}"
```

The IP rides in the query string from there. `/mod` passes `&ip=` through to
every panel link, and `render_ban_form` pre-fills both of its fields with
`value: params[:ip]?`. So the whole flow is four clicks and no typing:

**a bad post → Mod → Manage bans → create.**

The delete field is pre-filled from the same parameter, so arriving from a
post's Mod link also pre-loads the unban form with that address.

`/mod/ban` reached directly, with no `?ip=`, gives empty fields and the table
of existing bans — which is where you would read an address off, rather than
out of psql.

## What a ban is

```crystal
class Ban < Granite::Base
  column id : Int64, primary: true
  column ip_address : String?
  timestamps
end
```

That is the whole table. A ban has no reason, no expiry, no duration, and no
record of who applied it. `created_at` is the only clue to when, and nothing
reads it.

Bans are **permanent until deleted by hand**. There is no sweeper and no
"expires_at".

## What it does to the banned

`PostController#create` checks `Ban.exists?(ip_address: ip_address)` after
resolving the address, before creating anything. A banned poster is not told
they are banned and gets no error page:

```crystal
redirect_to("https://files.catbox.moe/glburl.mp4")
```

They are redirected off-site to a video. Reading is unaffected — the ban is
enforced only on the posting path, so a banned IP can still browse every board.

## What it cannot do

- **No ranges.** `ip_address` is compared as an exact string. No CIDR, no
  subnet, no wildcards. Banning `1.2.3.4` does nothing about `1.2.3.5`.
- **No IPv6 normalisation.** The address is whatever `X-Forwarded-For` said,
  split on `:` and truncated at the first colon — which is correct for
  `host:port` on IPv4 and wrong for IPv6, where it leaves a fragment of the
  address.
- **Dynamic IPs defeat it.** Reconnecting is enough.
- **Nothing is cached.** Every post submission costs one `Ban.exists?`
  query against the full table.

## Two defects worth knowing about

**The self-ban guard is on the wrong action and does not work.**
`BanController#delete` — *delete*, not create — checks:

```crystal
can_delete = params[:ip_address] != request.remote_address
```

and refuses with "You cannot ban yourself". Two problems. The message
describes creating a ban, not removing one, so the check reads like it was
meant for `create` and ended up on the wrong method. And the comparison cannot
match: `request.remote_address` includes the port (`1.2.3.4:54321`) and is the
socket peer, while bans store a bare address taken from `X-Forwarded-For`.
Behind a reverse proxy the peer is the proxy. So the guard always passes, and
a moderator can freely ban their own address — locking themselves out of
posting, though not out of `/mod`, which is unaffected by bans.

**Moderator IPs are in the page source.** Every post's Mod link contains that
poster's IP address in plain text. That is only served to authenticated
moderators, but it means an IP leaks into browser history, into any screenshot
of the board taken while logged in, and into the referrer of any outbound link
clicked from that page.

## If this is to be rebuilt

Carry over: the pre-filled form reached from the post itself. It is the good
part of the design — banning never requires knowing or typing an address.

Worth adding: a reason and an expiry (both columns and a check on read), the
moderator's identity, CIDR matching, and an honest message to the banned
person rather than an off-site redirect. Fix the self-ban guard by moving it
to `create` and comparing against the same `X-Forwarded-For`-derived address
the rest of the application uses.
