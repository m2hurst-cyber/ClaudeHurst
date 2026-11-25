# The style guide. It renders the Ledger design language on finance content so the
# look can be agreed before any existing screen is rebuilt around it.
class DesignController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    render layout: false
  end
end
