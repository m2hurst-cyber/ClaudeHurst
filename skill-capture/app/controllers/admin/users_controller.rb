module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[edit update]

    def index = @users = User.order(:name)
    def new = @user = User.new(role: "member")

    def create
      @user = User.new(user_params)
      password = SecureRandom.base58(16)
      @user.password = @user.password_confirmation = password
      if @user.save
        AuditLog.record("user.created", user: current_user, subject: @user, role: @user.role)
        flash[:notice] = "Created #{@user.email}. One-time password: #{password}. Share it securely; it is not shown again."
        redirect_to admin_users_path
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @user == current_user && user_params[:role].present? && user_params[:role] != "admin"
        return redirect_to(edit_admin_user_path(@user), alert: "You can't remove your own admin role.")
      end
      if @user.update(user_params)
        AuditLog.record("user.updated", user: current_user, subject: @user, role: @user.role, domains: @user.domains)
        redirect_to admin_users_path, notice: "Saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_user = @user = User.find(params[:id])

    def user_params
      p = params.require(:user).permit(:name, :email, :role, :domains, :department, :active)
      p[:domains] = p[:domains].to_s.split(",") if p.key?(:domains)
      p
    end
  end
end
