require "test_helper"

class IngestorTest < ActiveSupport::TestCase
  setup { @source, = make_source }

  def event(**over)
    { "action" => "excel.run_macro:close", "actor" => { "id" => "u-1", "name" => "Sam" },
      "session" => "s1", "occurred_at" => 1.hour.ago.utc.iso8601 }.merge(over.stringify_keys)
  end

  test "stores the minimum and drops everything not allowlisted" do
    r = Capture::Ingestor.call(@source, [event(
      "domain" => "Finance",
      "resource" => { "type" => "workbook", "ref" => "wb-381", "title" => "Q3 salaries.xlsx" },
      "context" => { "app" => "excel", "cell_value" => "123,456", "status" => "jane@example.com", "note" => "call Jane" },
      "label" => "Run the close macro",
      "body" => "free text that must not be stored"
    )])
    assert_equal 1, r.accepted
    assert_equal 3, r.dropped_fields
    e = UsageEvent.sole
    assert_equal({ "app" => "excel" }, e.context)
    assert_equal "finance", e.domain
    assert_equal %w[workbook wb-381], [e.resource_type, e.resource_ref]
    stored = e.attributes.to_json
    %w[salaries 123,456 jane@example.com Jane free\ text].each { |s| refute_includes stored, s }
    assert_equal "Run the close macro", ActionDefinition.find_by(key: "excel.run_macro:close").label
  end

  test "drops actor names that are email addresses" do
    Capture::Ingestor.call(@source, [event("actor" => { "id" => "u-1", "name" => "sam@example.com" })])
    assert_nil UsageEvent.sole.actor_name
  end

  test "rejects invalid events individually" do
    r = Capture::Ingestor.call(@source, [
      event, event("action" => "has spaces"), event("actor" => {}),
      event("occurred_at" => "yesterday"), event("occurred_at" => 1.day.from_now.iso8601)
    ])
    assert_equal 1, r.accepted
    assert_equal [1, 2, 3, 4], r.rejected.map { |x| x[:index] }
  end

  test "collector labels never overwrite admin-edited ones" do
    ActionDefinition.create!(key: "excel.run_macro:close", label: "Admin label")
    Capture::Ingestor.call(@source, [event("label" => "Collector label")])
    assert_equal "Admin label", ActionDefinition.find_by(key: "excel.run_macro:close").label
  end

  test "batch size is capped" do
    assert_raises(ArgumentError) { Capture::Ingestor.call(@source, Array.new(Capture::Config.max_batch + 1) { event }) }
  end
end
