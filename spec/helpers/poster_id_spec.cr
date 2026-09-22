require "../spec_helper"

describe PosterIdHelper do
  describe ".for" do
    it "is eight characters" do
      PosterIdHelper.for("203.0.113.7", 1).size.should eq(8)
    end

    it "is the same for one address on one board on one day" do
      # The whole point: two posts from one person are visibly one person.
      at = Time.utc(2026, 9, 21, 4, 0, 0)
      first = PosterIdHelper.for("203.0.113.7", 1, at)
      later = PosterIdHelper.for("203.0.113.7", 1, at + 6.hours)
      later.should eq(first)
    end

    it "differs between addresses" do
      at = Time.utc(2026, 9, 21)
      PosterIdHelper.for("203.0.113.7", 1, at)
        .should_not eq(PosterIdHelper.for("198.51.100.42", 1, at))
    end

    it "differs between boards, so one poster cannot be followed across them" do
      at = Time.utc(2026, 9, 21)
      PosterIdHelper.for("203.0.113.7", 1, at)
        .should_not eq(PosterIdHelper.for("203.0.113.7", 2, at))
    end

    it "rotates at midnight UTC, so an ID never becomes a handle" do
      ip = "203.0.113.7"
      before = PosterIdHelper.for(ip, 1, Time.utc(2026, 9, 21, 23, 59, 59))
      after = PosterIdHelper.for(ip, 1, Time.utc(2026, 9, 22, 0, 0, 1))
      after.should_not eq(before)
    end

    it "gives an ID to a post made without an address rather than none" do
      PosterIdHelper.for(nil, 1).size.should eq(8)
      PosterIdHelper.for(nil, 1).should eq(PosterIdHelper.for("", 1))
    end

    it "uses characters that survive being printed in a header" do
      # urlsafe Base64: no "+" or "/" to be mistaken for punctuation, and no
      # "=" padding, because six bytes is a whole number of Base64 characters.
      PosterIdHelper.for("203.0.113.7", 1).should match(/\A[A-Za-z0-9_-]{8}\z/)
    end

    it "is keyed, so the ID cannot be walked back to an address" do
      # A bare hash of an IPv4 address is a lookup table anybody can build.
      # Changing the key must change every ID.
      old = ENV["RATMACHINE_POSTER_ID_SECRET"]?
      at = Time.utc(2026, 9, 21)
      ENV["RATMACHINE_POSTER_ID_SECRET"] = "key-one"
      one = PosterIdHelper.for("203.0.113.7", 1, at)
      ENV["RATMACHINE_POSTER_ID_SECRET"] = "key-two"
      two = PosterIdHelper.for("203.0.113.7", 1, at)
      old ? (ENV["RATMACHINE_POSTER_ID_SECRET"] = old) : ENV.delete("RATMACHINE_POSTER_ID_SECRET")
      two.should_not eq(one)
    end
  end
end
