module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[show edit update destroy]

    def index
      @users = User.kept.order(:email)
    end

    def show; end

    def new
      @user = User.new(active: true, role: "sales")
    end

    def create
      @user = User.new(user_params)
      if @user.save
        AuditLogger.record(user: current_user, action: "user.created", subject: @user)
        redirect_to admin_users_path, notice: "User created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      attrs = user_params
      attrs.delete(:password) if attrs[:password].blank?
      attrs.delete(:password_confirmation) if attrs[:password_confirmation].blank?
      if @user.update(attrs)
        AuditLogger.record(user: current_user, action: "user.updated", subject: @user,
                           metadata: { changed: @user.saved_changes.keys })
        redirect_to admin_users_path, notice: "User updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @user == current_user
        redirect_to admin_users_path, alert: "Cannot remove yourself."
        return
      end

      if @user.destroy
        redirect_to admin_users_path, notice: "User deleted."
      else
        redirect_to admin_users_path, alert: @user.errors.full_messages.to_sentence.presence || "User could not be deleted."
      end
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:email, :first_name, :last_name, :role, :active, :password, :password_confirmation)
    end
  end
end
