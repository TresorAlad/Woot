# frozen_string_literal: true

require Rails.root.join('lib/converttrack/captain_knowledge_seeder')

def seed_assignment_notifications!(account:, user:)
  existing = Notification.where(
    account_id: account.id,
    user_id: user.id,
    notification_type: :conversation_assignment
  ).pluck(:primary_actor_id)

  account.conversations.open
         .where(assignee_id: user.id)
         .where.not(id: existing)
         .order(last_activity_at: :desc)
         .limit(5)
         .each do |conversation|
    NotificationBuilder.new(
      notification_type: 'conversation_assignment',
      user: user,
      account: account,
      primary_actor: conversation
    ).perform
  end
end

# Reassigne les donnees demo existantes vers le compte demo admin@techmentor.dev
email = ENV.fetch('CONVERTTRACK_DEMO_EMAIL', 'admin@techmentor.dev')
user = User.find_by!(email: email)
account = user.account_users.find_by!(role: :administrator).account

puts "[converttrack-demo] Patch admin demo pour #{email} (compte ##{account.id})"

Current.account = account
Current.user = user

account.enable_features!('captain_integration', 'captain_integration_v2')
settings = account.settings || {}
settings['converttrack_automation_mode'] = 'hybrid'
settings['converttrack_catalog_sources'] = [
  ENV.fetch('CONVERTTRACK_CATALOG_URL', 'http://127.0.0.1:3000/converttrack/demo_catalog.json')
]
account.update!(settings: settings)

account.inboxes.where('name LIKE ?', 'Demo %').find_each do |inbox|
  InboxMember.find_or_create_by!(inbox: inbox, user: user)
end

account.teams.limit(2).find_each do |team|
  TeamMember.find_or_create_by!(team: team, user: user)
end

open_conversations = account.conversations.open.to_a
live_cutoff = 4.hours.ago
live, others = open_conversations.partition { |c| c.last_activity_at && c.last_activity_at >= live_cutoff }

live.each { |c| c.update_columns(assignee_id: user.id, updated_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations
others.sample((others.size * 0.4).round).each { |c| c.update_columns(assignee_id: user.id, updated_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations

web_inbox = account.inboxes.find_by('name LIKE ?', 'Demo Site Web%')
assistant = account.captain_assistants.find_by(name: 'ConvertTrack Copilot')

unless assistant
  raise 'Inbox Demo Site Web introuvable' unless web_inbox

  assistant = Captain::Assistant.create!(
    account: account,
    name: 'ConvertTrack Copilot',
    description: 'Assistant demo ConvertTrack pour le site web.',
    config: { feature_faq: true, feature_memory: true, product_name: account.name }
  )
  CaptainInbox.create!(captain_assistant: assistant, inbox: web_inbox)
  puts '[converttrack-demo] Captain Copilot cree'
end

Converttrack::CaptainKnowledgeSeeder.seed!(account: account, assistant: assistant)
puts "[converttrack-demo] Captain knowledge: #{assistant.responses.count} FAQs, #{assistant.documents.count} documents"

seed_assignment_notifications!(account: account, user: user)

mine = account.conversations.open.where(assignee_id: user.id).count
notifications = user.notifications.where(account_id: account.id).count
puts "[converttrack-demo] Patch termine: #{mine} conversations ouvertes assignees, #{notifications} notifications"
