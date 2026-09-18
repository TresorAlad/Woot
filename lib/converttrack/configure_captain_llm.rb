# frozen_string_literal: true

module Converttrack
  module ConfigureCaptainLlm
    CONFIG_KEYS = {
      'CAPTAIN_OPEN_AI_API_KEY' => 'RODIUMAI_API_KEY',
      'CAPTAIN_OPEN_AI_MODEL' => 'RODIUMAI_MODEL',
      'CAPTAIN_OPEN_AI_ENDPOINT' => 'RODIUMAI_BASE_URL'
    }.freeze

    DEFAULT_MODEL = 'mistral/ministral-3-14b-instruct'
    DEFAULT_BASE_URL = 'https://api.rodiumai.io/v1'

    module_function

    def perform!
      api_key = ENV['RODIUMAI_API_KEY'].presence || ENV['CAPTAIN_OPEN_AI_API_KEY'].presence
      return { configured: false, reason: 'RODIUMAI_API_KEY manquant' } if api_key.blank?

      model = ENV.fetch('RODIUMAI_MODEL', DEFAULT_MODEL)
      endpoint = normalize_endpoint(ENV.fetch('RODIUMAI_BASE_URL', DEFAULT_BASE_URL))

      upsert_config!('CAPTAIN_OPEN_AI_API_KEY', api_key)
      upsert_config!('CAPTAIN_OPEN_AI_MODEL', model)
      upsert_config!('CAPTAIN_OPEN_AI_ENDPOINT', endpoint)

      Llm::Config.reset! if defined?(Llm::Config)

      { configured: true, model: model, endpoint: endpoint }
    end

    def normalize_endpoint(raw_url)
      url = raw_url.to_s.strip.chomp('/')
      url = url.sub(%r{/v1\z}, '')
      url.presence || 'https://api.rodiumai.io'
    end

    def upsert_config!(name, value)
      config = InstallationConfig.find_or_initialize_by(name: name)
      config.locked = false if config.new_record?
      config.value = value
      config.save!
    end
  end
end
