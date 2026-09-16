# frozen_string_literal: true

# Bootstrap idempotent ConvertTrack dans Chatwoot.
# Usage: rails runner /app/converttrack/scripts/chatwoot_bootstrap.rb

LABELS = [
  { title: 'intent-prix', color: '#1f93ff', description: 'Demande de prix' },
  { title: 'intent-disponibilite', color: '#0d9b8a', description: 'Disponibilite stock' },
  { title: 'intent-livraison', color: '#ffc532', description: 'Delais de livraison' },
  { title: 'intent-info', color: '#7b64ff', description: 'Information generale' },
  { title: 'intent-autre', color: '#93a1b0', description: 'Autre intention' },
  { title: 'pipeline-nouveau', color: '#1f93ff', description: 'Nouveau contact' },
  { title: 'pipeline-interet', color: '#0d9b8a', description: 'Interet confirme' },
  { title: 'pipeline-prix', color: '#ffc532', description: 'Prix envoye' },
  { title: 'pipeline-relance', color: '#ff6b6b', description: 'A relancer' },
  { title: 'pipeline-converti', color: '#27ae60', description: 'Converti' },
  { title: 'pipeline-perdu', color: '#576574', description: 'Perdu' },
  { title: 'priorite-haute', color: '#e74c3c', description: 'Priorite haute - traiter en premier' },
  { title: 'priorite-moyenne', color: '#f39c12', description: 'Priorite moyenne' },
  { title: 'priorite-basse', color: '#95a5a6', description: 'Priorite basse' }
].freeze

WEBHOOK_URL = ENV.fetch('CONVERTTRACK_WEBHOOK_URL', 'http://127.0.0.1:5000/webhook/chatwoot')
WEBHOOK_SECRET = ENV.fetch('WEBHOOK_SECRET', '')
WEBSITE_URL = ENV.fetch('CONVERTTRACK_WEBSITE_URL', 'http://127.0.0.1:8080')
TOKEN_PATH = '/shared/chatwoot_api_token'
WEBSITE_TOKEN_PATH = '/shared/website_token'
DEFAULT_AGENT_ID_PATH = '/shared/default_agent_id'
CAPTAIN_FEATURES = %w[
  captain_integration
  captain_integration_v2
  custom_tools
  captain_tasks
  captain_document_auto_sync
].freeze
CHANNEL_FEATURES = %w[
  channel_website
  channel_facebook
  channel_email
  channel_instagram
  channel_voice
  channel_tiktok
  api_and_webhooks
  inbound_emails
].freeze

def wait_for_chatwoot_api(max_attempts: 60)
  require 'net/http'
  uri = URI(ENV.fetch('CHATWOOT_BASE_URL', 'http://127.0.0.1:3000') + '/api')

  max_attempts.times do |attempt|
    begin
      response = Net::HTTP.get_response(uri)
      return true if response.code.to_i == 200
    rescue StandardError
      # retry
    end
    puts "[converttrack-setup] Attente Chatwoot (#{attempt + 1}/#{max_attempts})..."
    sleep 2
  end
  false
end

def ensure_account!
  account = Account.first
  return account if account.present?

  email = ENV['CONVERTTRACK_ADMIN_EMAIL']
  password = ENV['CONVERTTRACK_ADMIN_PASSWORD']
  if email.blank? || password.blank?
    raise 'Aucun compte Chatwoot. Definissez CONVERTTRACK_ADMIN_EMAIL/PASSWORD ou creez un compte via http://127.0.0.1:3000'
  end

  user, account = AccountBuilder.new(
    account_name: ENV.fetch('CONVERTTRACK_ACCOUNT_NAME', 'ConvertTrack'),
    email: email,
    user_full_name: ENV.fetch('CONVERTTRACK_ADMIN_NAME', 'ConvertTrack Admin'),
    user_password: password,
    confirmed: true
  ).perform

  puts "[converttrack-setup] Compte cree: #{account.name} (#{user.email})"
  account
end

def ensure_labels!(account)
  LABELS.each do |attrs|
    label = account.labels.find_or_initialize_by(title: attrs[:title])
    label.color = attrs[:color]
    label.description = attrs[:description]
    label.show_on_sidebar = true
    label.save!
  end
  puts "[converttrack-setup] Labels ConvertTrack OK (#{LABELS.size})"
end

def ensure_webhook!(account)
  webhook = account.webhooks.find_or_initialize_by(url: WEBHOOK_URL)
  webhook.name = 'ConvertTrack'
  webhook.subscriptions = ['message_created']
  webhook.webhook_type = :account_type
  webhook.secret = WEBHOOK_SECRET if WEBHOOK_SECRET.present?
  webhook.save!
  puts "[converttrack-setup] Webhook OK: #{WEBHOOK_URL}"
end

def ensure_website_inbox!(account)
  inbox = account.inboxes.find_by(channel_type: 'Channel::WebWidget')
  if inbox.blank?
    channel = account.web_widgets.create!(
      website_url: WEBSITE_URL,
      widget_color: '#1f93ff',
      welcome_title: 'ConvertTrack',
      welcome_tagline: 'Posez votre question, nous vous repondons rapidement.'
    )
    inbox = account.inboxes.create!(name: 'ConvertTrack Website', channel: channel)
    puts "[converttrack-setup] Inbox Website cree: #{inbox.name}"
  else
    inbox.update!(name: 'ConvertTrack Website')
    inbox.channel.update!(
      website_url: WEBSITE_URL,
      welcome_title: 'ConvertTrack',
      welcome_tagline: 'Posez votre question, nous vous repondons rapidement.'
    )
    puts "[converttrack-setup] Inbox Website OK: #{inbox.name}"
  end

  admin = account.administrators.first
  InboxMember.find_or_create_by!(inbox: inbox, user: admin) if admin.present?
  File.write(WEBSITE_TOKEN_PATH, inbox.channel.website_token)
  puts "[converttrack-setup] Website token ecrit dans #{WEBSITE_TOKEN_PATH}"
  inbox
end

def ensure_captain_enabled!(account)
  account.enable_features!(*CAPTAIN_FEATURES, *CHANNEL_FEATURES)
  limits = (account.limits || {}).merge(
    'captain_responses' => ChatwootApp.max_limit,
    'captain_documents' => ChatwootApp.max_limit
  )
  account.update!(limits: limits)
  attrs = (account.custom_attributes || {}).merge('plan_name' => 'enterprise')
  account.update!(custom_attributes: attrs)
  puts '[converttrack-setup] Captain active (features + limites illimitees)'
end

def write_api_token!(account)
  admin = account.administrators.first
  raise 'Aucun administrateur trouve sur le compte Chatwoot' if admin.blank?

  token = admin.access_token&.token
  raise "Token API introuvable pour #{admin.email}" if token.blank?

  File.write(TOKEN_PATH, token)
  puts "[converttrack-setup] Token API ecrit dans #{TOKEN_PATH}"
  File.write(DEFAULT_AGENT_ID_PATH, admin.id.to_s)
  puts "[converttrack-setup] Agent par defaut ecrit dans #{DEFAULT_AGENT_ID_PATH} (#{admin.email})"
end

raise 'Chatwoot API indisponible' unless wait_for_chatwoot_api

account = ensure_account!
ensure_captain_enabled!(account)
ensure_labels!(account)
ensure_website_inbox!(account)
ensure_webhook!(account)
write_api_token!(account)

puts '[converttrack-setup] Bootstrap termine'
