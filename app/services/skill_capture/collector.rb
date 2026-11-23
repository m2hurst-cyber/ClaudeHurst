module SkillCapture
  # Turns a finished controller request into a privacy-safe UsageEvent.
  # Only state-changing requests are captured: these are the "steps" of a workflow.
  class Collector
    CAPTURED_METHODS = %w[POST PATCH PUT DELETE].freeze

    def self.record(controller)
      new(controller).record
    end

    def initialize(controller)
      @controller = controller
      @request = controller.request
    end

    def record
      return unless capturable?

      UsageEvent.create!(
        user: @controller.current_user,
        session_key: session_key,
        workflow_key: workflow_key,
        http_method: @request.request_method,
        resource_type: resource_type,
        resource_id: resource_id,
        response_status: @controller.response.status,
        context: safe_context,
        occurred_at: Time.current
      )
    rescue => e
      # Capture must never break the user's request.
      Rails.logger.warn("SkillCapture::Collector skipped: #{e.class}: #{e.message}")
      nil
    end

    private

    def capturable?
      Config.enabled? &&
        @controller.current_user.present? &&
        CAPTURED_METHODS.include?(@request.request_method) &&
        !Config::EXCLUDED_CONTROLLERS.include?(@controller.controller_path) &&
        @controller.response.status.to_i < 400 &&
        @controller.flash[:alert].blank? # unauthorized / failed actions redirect with an alert
    end

    def workflow_key
      "#{@controller.controller_path}##{@controller.action_name}"
    end

    # A random per-browser-session key of our own (the real session id is never
    # stored, and Rails may rotate it mid-session, e.g. on first write).
    def session_key
      @controller.session[:skill_capture_key] ||= SecureRandom.hex(12)
    end

    def resource_type
      @controller.controller_name.classify
    end

    def resource_id
      id = @controller.params[:id]
      id.to_s.match?(/\A\d+\z/) ? id.to_i : nil
    end

    # Records *which* associations were involved (keys ending in _id, with integer ids)
    # and a handful of enum-like fields. Never free text, names, emails or amounts.
    def safe_context
      ctx = {}
      @controller.params.to_unsafe_h.each do |key, value|
        next if key.in?(%w[controller action id authenticity_token commit _method])
        if key.end_with?("_id") && value.to_s.match?(/\A\d+\z/)
          ctx[key] = value.to_i
        elsif value.is_a?(Hash)
          value.each do |k, v|
            k = k.to_s
            if k.end_with?("_id") && v.to_s.match?(/\A\d+\z/)
              ctx[k] = v.to_i
            elsif Config::CONTEXT_ALLOWLIST.include?(k) && v.to_s.match?(/\A[\w-]{1,40}\z/)
              ctx[k] = v.to_s
            end
          end
        end
      end
      ctx
    end
  end
end
