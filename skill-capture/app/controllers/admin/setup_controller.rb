module Admin
  # What this installation needs from outside, and whether it has it.
  class SetupController < BaseController
    def show
      @checks = Capture::Readiness.all
      @catalogue = Capture::Integrations.all
    end
  end
end
