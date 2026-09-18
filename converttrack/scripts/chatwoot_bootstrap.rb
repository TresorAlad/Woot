# frozen_string_literal: true

# Bootstrap plateforme Woot/ConvertTrack.
# Active toutes les capacites et configure chaque workspace existant.
# Usage: rails runner /app/converttrack/scripts/chatwoot_bootstrap.rb

require Rails.root.join('lib/converttrack/workspace_setup')
require Rails.root.join('lib/converttrack/configure_captain_llm')

WEBSITE_URL = ENV.fetch('CONVERTTRACK_WEBSITE_URL', 'http://127.0.0.1:8080')
TOKEN_PATH = '/shared/chatwoot_api_token'
WEBSITE_TOKEN_PATH = '/shared/website_token'
DEFAULT_AGENT_ID_PATH = '/shared/default_agent_id'

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

def enable_dashboard_account_creation!
  config = InstallationConfig.find_by(name: 'CREATE_NEW_ACCOUNT_FROM_DASHBOARD')
  return if config.blank?

  config.update!(value: true) unless ActiveModel::Type::Boolean.new.cast(config.value)
  puts '[converttrack-setup] CREATE_NEW_ACCOUNT_FROM_DASHBOARD active'
end

def ensure_first_account!
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

  puts "[converttrack-setup] Premier workspace cree: #{account.name} (#{user.email})"
  account
end

def ensure_website_inbox!(account)
  inbox = account.inboxes.find_by(channel_type: 'Channel::WebWidget')
  if inbox.blank?
    channel = account.web_widgets.create!(
      website_url: WEBSITE_URL,
      widget_color: '#1f93ff',
      welcome_title: account.name,
      welcome_tagline: 'Posez votre question, nous vous repondons rapidement.'
    )
    inbox = account.inboxes.create!(name: 'ConvertTrack Demo', channel: channel)
    puts "[converttrack-setup] Inbox demo interne cree (account #{account.id}, inbox #{inbox.id})"
  else
    inbox.channel.update!(website_url: WEBSITE_URL) if inbox.channel.website_url.blank?
    puts "[converttrack-setup] Inbox demo interne OK (account #{account.id}, inbox #{inbox.id})"
  end

  admin = account.administrators.first
  InboxMember.find_or_create_by!(inbox: inbox, user: admin) if admin.present?

  settings = account.settings || {}
  unless settings['converttrack_demo_inbox_id'].to_i == inbox.id
    settings['converttrack_demo_inbox_id'] = inbox.id
    account.update!(settings: settings)
  end

  inbox
end

def write_shared_tokens!(account)
  admin = account.administrators.first
  raise 'Aucun administrateur trouve sur le compte Chatwoot' if admin.blank?

  token = admin.access_token&.token
  raise "Token API introuvable pour #{admin.email}" if token.blank?

  File.write(TOKEN_PATH, token)
  puts "[converttrack-setup] Token API ecrit dans #{TOKEN_PATH}"

  File.write(DEFAULT_AGENT_ID_PATH, admin.id.to_s)
  puts "[converttrack-setup] Agent par defaut ecrit dans #{DEFAULT_AGENT_ID_PATH} (#{admin.email})"

  inbox = account.inboxes.find_by(channel_type: 'Channel::WebWidget')
  if inbox.present?
    File.write(WEBSITE_TOKEN_PATH, inbox.channel.website_token)
    puts "[converttrack-setup] Website token ecrit dans #{WEBSITE_TOKEN_PATH}"
  end
end

def bootstrap_all_workspaces!
  first_account = Account.first
  Account.find_each do |account|
    workspace_type = account.settings['converttrack_workspace_type'].presence || 'custom'
    Converttrack::WorkspaceSetup.setup_account!(account, workspace_type: workspace_type)
    ensure_website_inbox!(account) if account.id == first_account&.id
    puts "[converttrack-setup] Workspace configure: #{account.name} (##{account.id})"
  end
end

raise 'Chatwoot API indisponible' unless wait_for_chatwoot_api

captain_llm = Converttrack::ConfigureCaptainLlm.perform!
if captain_llm[:configured]
  puts "[converttrack-setup] Captain LLM: #{captain_llm[:model]} @ #{captain_llm[:endpoint]}"
else
  puts "[converttrack-setup] Captain LLM ignore: #{captain_llm[:reason]}"
end

enable_dashboard_account_creation!
first_account = ensure_first_account!
bootstrap_all_workspaces!
write_shared_tokens!(first_account)
Converttrack::WorkspaceSetup.refresh_account_tokens_map!

puts '[converttrack-setup] Bootstrap plateforme termine'
