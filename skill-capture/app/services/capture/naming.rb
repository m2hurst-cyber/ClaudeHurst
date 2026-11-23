module Capture
  module Naming
    module_function

    # Agent Skills name: kebab-case, <= 64 chars, cut at a word boundary.
    def skill_name(text)
      slug = text.to_s.parameterize
      return slug if slug.length <= 64
      cut = slug.first(65)
      (cut.rindex("-") ? cut[0...cut.rindex("-")] : slug.first(64)).sub(/-+\z/, "")
    end
  end
end
