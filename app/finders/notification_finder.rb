class NotificationFinder
  attr_reader :current_user, :current_account, :params

  RESULTS_PER_PAGE = 15

  def initialize(current_user, current_account, params = {})
    @current_user = current_user
    @current_account = current_account
    @params = params
    set_up
  end

  def notifications
    ordered_notifications.page(current_page).per(RESULTS_PER_PAGE)
  end

  def unread_count
    if type_included?('read')
      # If we're including read notifications, filter to unread
      @notifications.where(read_at: nil).count
    else
      # Already filtered to unread notifications, just count
      @notifications.count
    end
  end

  def count
    @notifications.count
  end

  private

  def set_up
    find_all_notifications
    filter_snoozed_notifications
    filter_read_notifications
  end

  def find_all_notifications
    @notifications = current_user.notifications.where(account_id: @current_account.id).includes(
      :user,
      :secondary_actor,
      primary_actor: [:contact, :assignee, :inbox, :team, :contact_inbox]
    )
  end

  def filter_snoozed_notifications
    @notifications = @notifications.where(snoozed_until: nil) unless type_included?('snoozed')
  end

  def filter_read_notifications
    @notifications = @notifications.where(read_at: nil) unless type_included?('read')
  end

  def type_included?(type)
    (params[:includes] || []).include?(type)
  end

  def current_page
    params[:page] || 1
  end

  def sort_order
    params[:sort_order]&.to_sym || :desc
  end

  def ordered_notifications
    return @notifications.order(last_activity_at: :asc) if sort_order == :asc

    @notifications
      .joins(relevance_join_sql)
      .reorder(
        Arel.sql('CASE WHEN notifications.read_at IS NULL THEN 0 ELSE 1 END'),
        Arel.sql('COALESCE(conversations.priority, 0) DESC'),
        Notification.arel_table[:last_activity_at].desc
      )
  end

  def relevance_join_sql
    <<~SQL.squish
      LEFT JOIN conversations
        ON conversations.id = notifications.primary_actor_id
       AND notifications.primary_actor_type = 'Conversation'
    SQL
  end
end
