# frozen_string_literal: true

module Converttrack
  module WorkspaceSetup
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

    PLATFORM_FEATURES = (
      CAPTAIN_FEATURES + CHANNEL_FEATURES + %w[
        agent_management
        team_management
        inbox_management
        labels
        custom_attributes
        automations
        macros
        canned_responses
        campaigns
        help_center
        integrations
        agent_bots
        assignment_v2
        custom_roles
        sla
      ]
    ).freeze

    DEFAULT_SETTINGS = {
      'converttrack_automation_mode' => 'classification',
      'converttrack_workspace_type' => 'custom'
    }.freeze

    module_function

    def webhook_url
      ENV.fetch('CONVERTTRACK_WEBHOOK_URL', 'http://127.0.0.1:5000/webhook/chatwoot')
    end

    def webhook_secret
      ENV.fetch('WEBHOOK_SECRET', '')
    end

    def setup_account!(account, workspace_type: 'custom')
      enable_platform_features!(account)
      apply_default_settings!(account, workspace_type: workspace_type)
      ensure_labels!(account)
      ensure_webhook!(account)
      refresh_account_tokens_map!
      notify_converttrack!(account, workspace_type: workspace_type)
      account
    end

    def enable_platform_features!(account)
      account.enable_features!(*PLATFORM_FEATURES)
      limits = (account.limits || {}).merge(
        'captain_responses' => ChatwootApp.max_limit,
        'captain_documents' => ChatwootApp.max_limit
      )
      account.update!(
        limits: limits,
        custom_attributes: (account.custom_attributes || {}).merge('plan_name' => 'enterprise')
      )
    end

    def apply_default_settings!(account, workspace_type: 'custom')
      settings = account.settings || {}
      DEFAULT_SETTINGS.each do |key, value|
        settings[key] = value if settings[key].blank?
      end
      settings['converttrack_workspace_type'] = workspace_type if workspace_type.present?
      account.update!(settings: settings)
    end

    def ensure_labels!(account)
      LABELS.each do |attrs|
        label = account.labels.find_or_initialize_by(title: attrs[:title])
        label.color = attrs[:color]
        label.description = attrs[:description]
        label.show_on_sidebar = true
        label.save!
      end
    end

    def ensure_webhook!(account)
      webhook = account.webhooks.find_or_initialize_by(url: webhook_url)
      webhook.name = 'ConvertTrack'
      webhook.subscriptions = ['message_created']
      webhook.webhook_type = :account_type
      webhook.secret = webhook_secret if webhook_secret.present?
      webhook.save!
    end

    def account_tokens_path
      ENV.fetch('ACCOUNT_TOKENS_PATH', '/shared/account_tokens.json')
    end

    def refresh_account_tokens_map!
      tokens = {}
      Account.find_each do |item|
        admin = item.administrators.first
        token = admin&.access_token&.token
        tokens[item.id.to_s] = token if token.present?
      end
      File.write(account_tokens_path, tokens.to_json)
    rescue StandardError => e
      Rails.logger.warn("[Converttrack] Account tokens map update failed: #{e.message}")
    end

    def notify_converttrack!(account, workspace_type: 'custom')
      base_url = ENV.fetch('CONVERTTRACK_BASE_URL', 'http://127.0.0.1:5000').chomp('/')
      uri = URI("#{base_url}/api/workspaces/#{account.id}/setup")
      catalog_sources = Array(account.settings['converttrack_catalog_sources']).select(&:present?)
      payload = {
        account_id: account.id,
        account_name: account.name,
        workspace_type: workspace_type,
        automation_mode: account.settings['converttrack_automation_mode'] || 'classification',
        catalog_sources: catalog_sources
      }
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 5
      http.read_timeout = 5
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request['X-ConvertTrack-Secret'] = webhook_secret if webhook_secret.present?
      request.body = payload.to_json
      response = http.request(request)
      return if response.code.to_i < 400

      Rails.logger.warn("[Converttrack] Setup notification failed for account #{account.id}: #{response.code}")
    rescue StandardError => e
      Rails.logger.warn("[Converttrack] Setup notification skipped for account #{account.id}: #{e.message}")
    end
  end
end
