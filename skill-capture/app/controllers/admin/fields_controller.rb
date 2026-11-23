module Admin
  # The field taxonomy: add, rename, move, tune keywords, remove.
  class FieldsController < BaseController
    def index
      Capture::Taxonomy.ensure_defaults!
      @tree = Field.tree
      @counts = SkillClassification.group(:field_id).count
      @field = Field.new
    end

    def create
      @field = Field.new(field_params)
      if @field.save
        AuditLog.record("field.created", user: current_user, subject: @field, path: @field.path)
        redirect_to admin_fields_path, notice: "Added #{@field.label}."
      else
        redirect_to admin_fields_path, alert: @field.errors.full_messages.to_sentence
      end
    end

    def update
      field = Field.find(params[:id])
      if field.update(field_params)
        AuditLog.record("field.updated", user: current_user, subject: field, path: field.path)
        redirect_to admin_fields_path, notice: "Saved #{field.label}."
      else
        redirect_to admin_fields_path, alert: field.errors.full_messages.to_sentence
      end
    end

    def destroy
      field = Field.find(params[:id])
      if field.children.exists?
        redirect_to admin_fields_path, alert: "Remove or move #{field.name}'s subfields first."
      else
        SkillClassification.where(field: field, confirmed: false).update_all(field_id: nil)
        field.destroy!
        AuditLog.record("field.removed", user: current_user, path: field.path)
        redirect_to admin_fields_path, notice: "Removed #{field.name}. Skills classified under it will be re-inferred at the next sweep."
      end
    end

    private

    def field_params
      p = params.require(:field).permit(:name, :parent_id, :keywords, :position)
      p[:keywords] = p[:keywords].to_s.split(",") if p.key?(:keywords)
      p
    end
  end
end
