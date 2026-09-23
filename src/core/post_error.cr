# Why a post was refused, as a short code.
#
# The code travels in the query string on the way back to the board and is
# reflected into the page, so it is deliberately not the message text itself:
# a code cannot be used to put words of an attacker's choosing in front of a
# reader, and it keeps an already long URL (the message rides there too) from
# growing further.
#
# An unrecognised status maps to "invalid" rather than passing through. That
# matters for CreatePost's `rescue error : ArgumentError`, whose message comes
# from a library and must never reach a URL. It also means a reworded check
# fails closed -- a vague message -- rather than a specific wrong one.
module PostError
  MESSAGES = {
    "captcha" => "Incorrect or expired CAPTCHA",
    "empty"   => "Message empty",
    "long"    => "Message too long",
    "filter"  => "You just posted cringe, you are going to lose subscribers",
    "missing" => "The post you're trying to reply to does not exist",
    "invalid" => "Post rejected",
  }

  CODES = MESSAGES.invert

  # A status string from a use case becomes a code. nil in, nil out.
  def self.code_for(status : String?) : String?
    return nil if status.nil? || status.empty?
    CODES[status]? || "invalid"
  end

  # A code from the query string becomes a message. Anything unrecognised --
  # including a hand-edited URL -- renders nothing at all.
  def self.message_for(code : String?) : String?
    return nil if code.nil?
    MESSAGES[code.strip]?
  end
end
