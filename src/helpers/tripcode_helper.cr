require "openssl/hmac"

module TripcodeHelper
  # Store only the display name and keyed digest, never the supplied secret.
  # A persistent key keeps codes stable across app restarts.
  def self.parse(input : String?)
    parts = input.to_s.split('#', 2)
    name = parts[0].strip
    secret = parts[1]?
    raise ArgumentError.new("Name must be 80 characters or fewer") if name.size > 80
    raise ArgumentError.new("Tripcode secret must be 128 characters or fewer") if !secret.nil? && secret.size > 128
    tripcode = if secret.nil? || secret.empty?
      nil
    else
      key = ENV["RATMACHINE_TRIPCODE_SECRET"]? || Amber.settings.secret_key_base
      OpenSSL::HMAC.hexdigest(:sha256, key, "ratmachine-tripcode\u0000#{secret}")[0, 10]
    end
    {name: name.empty? ? nil : name, tripcode: tripcode}
  end
end
