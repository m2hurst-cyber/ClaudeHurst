# Where the skills live: every area (domain), how mature its know-how is, and its gaps.
class SkillMapsController < ApplicationController
  def show
    @areas = Capture::SkillMap.call
    @max = [@areas.map(&:total).max.to_i, 1].max
    respond_to do |format|
      format.html
      format.json do
        render json: @areas.map { |a|
          a.to_h.slice(:name, :published, :awaiting_review, :detected, :apps).merge(
            total: a.total, reviewers: a.reviewers, contributors: a.contributors, gaps: a.gaps)
        }
      end
    end
  end
end
