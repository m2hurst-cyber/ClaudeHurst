ENV["RAILS_ENV"] ||= "test"
ENV["SKILL_CAPTURE_LLM"] = "off" # tests never call a real model
require "tmpdir"
ENV["SKILL_CAPTURE_REST_STOP_DIR"] = Dir.mktmpdir("rest-stops") # rest stop mirrors stay out of the project
ENV["SKILL_CAPTURE_PROVENANCE_DIR"] = Dir.mktmpdir("provenance") # so do anchor mirrors
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

module ActiveSupport
  class TestCase
    parallelize(workers: 1)
    include CaptureHelpers

    # Most tests exercise features of firm-wide skills; gatekeeping tests switch this to "local".
    setup { PromotionPolicy.current.update!(initial_stage: "firm") }
  end
end
