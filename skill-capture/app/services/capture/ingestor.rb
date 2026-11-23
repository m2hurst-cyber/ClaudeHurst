module Capture
  # Validates and minimizes a batch of events from a collector.
  #
  # Accepted event shape (JSON):
  #   {
  #     "action":      "excel.run_macro:quarterly_close",   # required, the step
  #     "label":       "Run the quarterly-close macro",      # optional, registers what the step means
  #     "domain":      "finance",                            # optional, area of work
  #     "actor":       { "id": "u-7f3a", "name": "Sam" },    # required id (pseudonymous is fine)
  #     "session":     "b1c2...",                            # optional, collector's session id
  #     "occurred_at": "2026-11-20T14:03:00Z",               # required
  #     "resource":    { "type": "workbook", "ref": "wb-381" },
  #     "context":     { "app": "excel", "status": "ok" }    # only allowlisted keys survive
  #   }
  #
  # Everything else is dropped. Values that look like emails or free text are
  # discarded rather than stored.
  class Ingestor
    Result = Struct.new(:accepted, :rejected, :dropped_fields, keyword_init: true)

    ACTION_FORMAT = %r{\A[\w.:\-/#]{1,160}\z}
    TOKEN_FORMAT = /\A[\w.:\-]{1,64}\z/
    EMAILISH = /@|\s/

    def self.call(source, events, actor: nil) = new(source, actor: actor).call(events)

    # actor: a User. When given (the Office add-in path), every event is attributed
    # to that signed-in person and any actor in the payload is ignored.
    def initialize(source, actor: nil)
      @source = source
      @actor = actor
    end

    def call(events)
      events = Array(events)
      raise ArgumentError, "batch too large (max #{Config.max_batch})" if events.size > Config.max_batch

      rows = []
      rejected = []
      dropped = 0
      definitions = {}
      now = Time.current

      events.each_with_index do |raw, i|
        e = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
        e = e.deep_stringify_keys
        error, row, d = build_row(e, now)
        if error
          rejected << { index: i, error: error }
        else
          rows << row
          dropped += d
          if e["label"].present?
            definitions[row[:action_key]] = { label: e["label"].to_s.squish.first(200), domain: row[:domain] }
          end
        end
      end

      UsageEvent.insert_all!(rows) if rows.any?
      register_definitions(definitions)
      @source.update_columns(last_seen_at: now)
      Result.new(accepted: rows.size, rejected: rejected, dropped_fields: dropped)
    end

    private

    def build_row(e, now)
      action = e["action"].to_s
      return ["action missing or invalid"] unless action.match?(ACTION_FORMAT)

      actor = if @actor
        { "id" => @actor.actor_key, "name" => @actor.name }
      else
        e["actor"].is_a?(Hash) ? e["actor"] : {}
      end
      actor_key = actor["id"].to_s
      return ["actor.id missing or invalid"] unless actor_key.match?(TOKEN_FORMAT)

      occurred_at = begin
        Time.iso8601(e["occurred_at"].to_s)
      rescue ArgumentError
        nil
      end
      return ["occurred_at missing or not ISO 8601"] unless occurred_at
      return ["occurred_at is in the future"] if occurred_at > now + 5.minutes

      dropped = 0
      domain = token(e["domain"])&.downcase
      session = token(e["session"]) || "default"
      resource = e["resource"].is_a?(Hash) ? e["resource"] : {}
      context = {}
      (e["context"].is_a?(Hash) ? e["context"] : {}).each do |k, v|
        if Config.context_keys.include?(k.to_s) && (t = token(v))
          context[k.to_s] = t
        else
          dropped += 1
        end
      end
      name = actor["name"].to_s.squish.first(80).presence
      name = nil if name&.include?("@")

      [nil, {
        source_id: @source.id,
        actor_key: actor_key,
        actor_name: name,
        session_key: session,
        action_key: action,
        domain: domain,
        resource_type: token(resource["type"]),
        resource_ref: token(resource["ref"]),
        context: context,
        occurred_at: occurred_at,
        created_at: now
      }, dropped]
    end

    def token(v)
      s = v.to_s
      s.match?(TOKEN_FORMAT) && !s.match?(EMAILISH) ? s : nil
    end

    def register_definitions(definitions)
      definitions.each do |key, attrs|
        defn = ActionDefinition.find_or_initialize_by(key: key)
        next if defn.persisted? # admin edits win over collector labels
        defn.update(label: attrs[:label], domain: attrs[:domain], source: @source)
      end
    end
  end
end
