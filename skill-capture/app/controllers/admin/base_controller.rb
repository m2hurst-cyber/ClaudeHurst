module Admin
  class BaseController < ApplicationController
    before_action { raise Pundit::NotAuthorizedError unless current_user.admin? }
  end
end
