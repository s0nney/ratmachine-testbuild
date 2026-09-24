require "../../spec_helper"
require "../../../src/core/live/event_log"

describe Live::EventLog do
  it "rejects cursors from a previous server or an invalid client" do
    log = Live::EventLog.new
    log.since(1, 8).should eq(:reload)
    log.append(1, :created, 100)
    log.since(1, 8).should eq(:reload)
    log.since(1, -1).should eq(:reload)
  end
  it "hands out increasing sequence numbers per board" do
    log = Live::EventLog.new(capacity: 10)
    log.append(1, :created, 100).should eq(1)
    log.append(1, :created, 101).should eq(2)
    log.append(2, :created, 200).should eq(1)
  end

  it "returns only events after the caller's sequence" do
    log = Live::EventLog.new(capacity: 10)
    log.append(1, :created, 100)
    seq = log.append(1, :created, 101)
    log.append(1, :changed, 102)
    events = log.since(1, seq)
    events.should be_a(Array(Live::Event))
    events.as(Array(Live::Event)).map(&.post_id).should eq([102])
  end

  it "tells a caller whose sequence fell off the ring to reload" do
    log = Live::EventLog.new(capacity: 2)
    3.times { |i| log.append(1, :created, i) }
    log.since(1, 0).should eq(:reload)
  end

  it "treats an unknown board as empty rather than a reload" do
    log = Live::EventLog.new(capacity: 10)
    log.since(99, 0).should eq([] of Live::Event)
  end

  it "reports the current sequence so a page can embed it" do
    log = Live::EventLog.new(capacity: 10)
    log.append(1, :created, 100)
    log.current_seq(1).should eq(1)
    log.current_seq(2).should eq(0)
  end
end
