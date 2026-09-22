require "openssl/hmac"
require "base64"

# Kareha-style poster IDs.
#
# The boards this imitates print a short code beside every message so that the
# people in a conversation can be told apart without anybody having to give a
# name. That is all this is for: it distinguishes posters, and it is not an
# account, not a claim, and not something anybody chooses.
#
# WHAT IT IS MADE FROM: the address the post came from, the board it went to,
# and the UTC date, through an HMAC with a server-side key. The key is what
# makes it safe to publish. IPv4 is four billion values, so a bare hash of an
# address is a lookup table anybody can build; keyed, the same list cannot be
# built without the key.
#
# WHAT IT COSTS, said plainly: two posts from one address to one board on one
# day are publicly, permanently linked. That is the feature. It also means the
# ID says "same poster" rather than "this person", and it stops saying anything
# at midnight UTC.
module PosterIdHelper
  # Six bytes, which is exactly eight Base64 characters — no padding to strip
  # and nothing to truncate unevenly. Long enough that two posters on one board
  # on one day are very unlikely to collide, short enough to sit in a header.
  ID_BYTES = 6

  # The daily rotation. A poster's ID changes at midnight UTC, which is what
  # keeps it from becoming a handle people build a reputation on — and what
  # keeps it from tracking somebody across weeks.
  def self.period(at : Time) : String
    at.to_utc.to_s("%Y-%m-%d")
  end

  def self.key : String
    ENV["RATMACHINE_POSTER_ID_SECRET"]? || Amber.settings.secret_key_base
  end

  # An ID for one post. `board_id` is nil only for a board row, which never
  # gets one — see the caller.
  #
  # A nil or empty address hashes as the empty string rather than raising:
  # every post gets an ID, and posts made without an address (a console, a
  # test) all share one rather than having none.
  def self.for(ip_address : String?, board_id : Int32 | Int64 | Nil, at : Time = Time.utc) : String
    material = String.build do |io|
      io << "ratmachine-poster-id" << '\0'
      io << ip_address.to_s << '\0'
      io << board_id.to_s << '\0'
      io << period(at)
    end
    digest = OpenSSL::HMAC.digest(:sha256, key, material)
    Base64.urlsafe_encode(digest[0, ID_BYTES])
  end
end
