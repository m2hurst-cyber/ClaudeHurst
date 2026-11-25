module Mcp
  # The ten tools Skill Capture exposes over MCP, so any agent can look up how this company does
  # something, follow the road, pick up the work assigned to it, run a job and report what it cost.
  #
  # A caller is either an agent (a Source token: sees shared skills, and the tasks addressed to it) or
  # a person (an add-in token: sees what they can see). Each tool says plainly what it needs and
  # returns JSON a model can read without further explanation.
  module Registry
    module_function

    def tools = TOOLS

    def find(name) = TOOLS.find { |t| t[:name] == name.to_s }

    def call(name, args, ctx)
      tool = find(name) or raise Error.new(-32_601, "No tool named #{name}")
      args = (args || {}).to_h.deep_stringify_keys
      missing = Array(tool.dig(:input_schema, :required)) - args.keys.select { |k| args[k].present? || args[k] == false }
      raise Error.new(-32_602, "#{name} needs #{missing.to_sentence}") if missing.any?
      Handlers.public_send(tool[:handler], args, ctx)
    end

    class Error < StandardError
      attr_reader :code
      def initialize(code, message) = (@code = code) && super(message)
    end

    def str(desc, **o) = { type: "string", description: desc, **o }
    def int(desc, **o) = { type: "integer", description: desc, **o }

    TOOLS = [
      { name: "search_skills", handler: :search_skills,
        title: "Search the skill library",
        description: "Find how this company does something. Searches published skills by words, area, Office app and level (mine, department, firm, industry, global). Returns names, titles, descriptions and what each one costs to run.",
        input_schema: { type: "object", properties: {
          query: str("Words to look for in the title, description or tags"),
          area: str("Area (domain) to limit to, e.g. bql, factset, field-services, tax"),
          app: str("Office app the skill is for", enum: %w[Excel Word PowerPoint Outlook Teams]),
          level: str("Whose skills to show", enum: Skill::LEVELS),
          limit: int("How many to return (default 20, max 100)")
        }, required: [] } },

      { name: "find_anything", handler: :find_anything,
        title: "Ask the front door",
        description: "One question, answered across everything this company knows: skills, the playbooks a job runs through, jobs in flight, flows, templates, formula commands and approved macros. Start here when you don't know which of those you want; use search_skills when you know it's a procedure.",
        input_schema: { type: "object", properties: {
          question: str("What you are trying to do, in your own words"),
          limit: int("Answers per group (default 5)")
        }, required: %w[question] } },

      { name: "get_skill", handler: :get_skill,
        title: "Read one skill",
        description: "The whole skill: its SKILL.md, the directions for the road it sits on, the resources it calls for, what it costs to run, any approved macro that does it without the AI, and the worksheet blueprint when it builds a sheet.",
        input_schema: { type: "object", properties: {
          name: str("The skill's name, e.g. bql-dcf-valuation"),
          markdown: { type: "boolean", description: "Return it as one Markdown document instead of JSON (default false)" }
        }, required: %w[name] } },

      { name: "find_route", handler: :find_route,
        title: "Follow the map",
        description: "What comes next after a skill, or the chain of skills between two of them, with the directions written for each leg. Use before starting work to see the whole road, not just the step in front of you.",
        input_schema: { type: "object", properties: {
          from: str("The skill to start from"),
          to: str("Optional: the skill to end at. Without it, returns what usually comes next.")
        }, required: %w[from] } },

      { name: "list_playbooks", handler: :list_playbooks,
        title: "List the playbooks",
        description: "The curated workflows a job or a return can be run through: their steps, the branches a job can take, and the documents each one expects.",
        input_schema: { type: "object", properties: { key: str("Optional: one playbook's key, for its full detail") }, required: [] } },

      { name: "start_job", handler: :start_job,
        title: "Start a job or a return",
        description: "Opens a run of a playbook with a reference of your choosing (a job number, a client, a return year). Returns the road it will follow and what the first leg needs. Needs a person's token, not an agent's.",
        input_schema: { type: "object", properties: {
          playbook: str("The playbook's key, e.g. roofing-solar"),
          reference: str("Your reference for this job or return, e.g. J-2041"),
          answers: { type: "object", description: "Situation key to yes/no/unsure, deciding which branches the job takes", additionalProperties: { type: "string" } }
        }, required: %w[playbook reference] } },

      { name: "get_job", handler: :get_job,
        title: "Read a job or a return",
        description: "Where a run has got to: each leg with its status, the figures taken off its documents, the checks that pass and the ones still blocking, and what is needed next.",
        input_schema: { type: "object", properties: {
          reference: str("The job's reference, e.g. J-2041"),
          id: int("Or the run's id")
        }, required: [] } },

      { name: "add_job_document", handler: :add_job_document,
        title: "Add a document to a job",
        description: "Puts a document in the job's jacket (a permit, a signed contract, a pay application, a lien waiver) with the figures read off it, so the legs that depend on it can verify. Needs a person's token.",
        input_schema: { type: "object", properties: {
          reference: str("The job's reference"),
          kind: str("The document kind from the playbook's catalogue, e.g. permit, signed-contract, pay-application"),
          fields: { type: "object", description: "Field key to value, as the catalogue defines them", additionalProperties: { type: "string" } },
          filename: str("A filename for the record"),
          content_base64: str("Optional: the file itself, base64 encoded (PDF or image)"),
          status: str("confirmed when the figures have been checked, otherwise read", enum: %w[read confirmed])
        }, required: %w[reference kind fields] } },

      { name: "list_tasks", handler: :list_tasks,
        title: "What work is waiting for me",
        description: "The flow tasks addressed to this agent (or person): what to do, in which app, the instructions, the skill to follow, what the previous task handed over, and how to report back when it is done.",
        input_schema: { type: "object", properties: { limit: int("How many (default 10)") }, required: [] } },

      { name: "complete_task", handler: :complete_task,
        title: "Finish a task and hand off",
        description: "Marks your flow task (or your part of a split task) done, records what you did and what it cost, and hands the flow to whoever does the next one.",
        input_schema: { type: "object", properties: {
          flow_run_id: int("From list_tasks"),
          step: int("The task's index, from list_tasks"),
          part: str("For a split task, the id of your part"),
          note: str("What you did, or where the output is"),
          model: str("The model you ran on"),
          input_tokens: int("Tokens in"),
          output_tokens: int("Tokens out"),
          duration_ms: int("How long it took, in milliseconds")
        }, required: %w[flow_run_id step] } },

      { name: "report_usage", handler: :report_usage,
        title: "Report what a skill cost to run",
        description: "Records a run of a skill: the model, tokens in and out, how long it took, and whether it worked. This is what makes the library's cost estimates real, so report every run. You can also hand over a macro that would do the same task without the AI next time.",
        input_schema: { type: "object", properties: {
          skill: str("The skill's name"),
          model: str("The model it ran on"),
          input_tokens: int("Tokens in"),
          output_tokens: int("Tokens out"),
          duration_ms: int("How long it took, in milliseconds"),
          status: str("succeeded or failed", enum: %w[succeeded failed]),
          trial_of: str("A label grouping runs of the same task tried on several models"),
          macro_code: str("Optional: a deterministic script that would do this task again, for review"),
          macro_language: str("The script's language", enum: MacroReview::LANGUAGES)
        }, required: %w[skill] } }
    ].freeze
  end
end
