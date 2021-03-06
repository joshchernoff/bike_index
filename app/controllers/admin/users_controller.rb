class Admin::UsersController < Admin::BaseController
  include SortableTable
  before_action :set_period, only: [:index]
  before_action :find_user, only: [:show, :edit, :update, :destroy]

  def index
    page = params[:page] || 1
    per_page = params[:per_page] || 25
    @users = matching_users.reorder("users.#{sort_column} #{sort_direction}").page(page).per(per_page)
  end

  def show
    redirect_to edit_admin_user_url(@user&.id)
  end

  def edit
    # urls with user IDs rather than usernames are more helpful in superadmin
    if params[:id] == @user.username
      redirect_to edit_admin_user_path(@user.id)
    end
    # If the user has a bunch of bikes, it can cause timeouts. In those cases, use rough approximation
    bikes = if @user.rough_approx_bikes.count > 25
      @user.rough_approx_bikes
    else
      @user.bikes
    end
    @bikescount = @user.bikes.count
    @bikes = bikes.reorder(created_at: :desc).limit(10)
  end

  def update
    @user.name = params[:user][:name]
    @user.email = params[:user][:email]
    @user.superuser = params[:user][:superuser]
    @user.developer = params[:user][:developer] if current_user.developer?
    @user.banned = params[:user][:banned]
    @user.username = params[:user][:username]
    @user.can_send_many_stolen_notifications = params[:user][:can_send_many_stolen_notifications]
    @user.phone = params[:user][:phone]
    if @user.save
      @user.update_auth_token("auth_token") if @user.banned? # Force reauthentication for the user
      @user.confirm(@user.confirmation_token) if params[:user][:confirmed]
      redirect_to admin_users_url, notice: "User Updated"
    else
      bikes = @user.bikes
      @bikes = BikeDecorator.decorate_collection(bikes)
      render action: :edit
    end
  end

  def destroy
    @user.destroy
    redirect_to admin_users_url, notice: "User Deleted."
  end

  helper_method :matching_users

  protected

  def sortable_columns
    %w[created_at email]
  end

  def earliest_period_date
    Time.at(1357912007)
  end

  def find_user
    @user = User.username_friendly_find(params[:id])
    raise ActiveRecord::RecordNotFound unless @user.present?
  end

  def matching_users
    @search_ambassadors = ParamsNormalizer.boolean(params[:search_ambassadors])
    @search_banned = ParamsNormalizer.boolean(params[:search_banned])
    @search_superusers = ParamsNormalizer.boolean(params[:search_superusers])
    users = if current_organization.present?
      current_organization.users
    else
      User
    end
    users = users.ambassadors if @search_ambassadors
    users = users.superusers if @search_superusers
    users = users.banned if @search_banned
    users = users.admin_text_search(params[:query]) if params[:query].present?
    if params[:search_phone].present?
      users = users.search_phone(params[:search_phone])
    end
    users.where(created_at: @time_range)
  end
end
