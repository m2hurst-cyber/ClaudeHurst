ENV["RAILS_ENV"] ||= "test"
ENV["SKILL_CAPTURE_LLM"] = "off" # tests never call a real model
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

module ActiveSupport
  class TestCase
    parallelize(workers: 1)
    include CaptureHelpers
  end
end
