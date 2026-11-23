ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

module ActiveSupport
  class TestCase
    parallelize(workers: 1)
    include FactoryBot::Syntax::Methods if defined?(FactoryBot)
    include SkillCaptureHelpers
  end
end
