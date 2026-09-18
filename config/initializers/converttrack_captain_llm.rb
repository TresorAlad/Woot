# frozen_string_literal: true

Rails.application.config.after_initialize do
  next unless ENV['RODIUMAI_API_KEY'].present?

  require Rails.root.join('lib/converttrack/configure_captain_llm')

  result = Converttrack::ConfigureCaptainLlm.perform!
  next if result[:configured]

  Rails.logger.warn("[Converttrack] Captain LLM non configure: #{result[:reason]}")
rescue StandardError => e
  Rails.logger.error("[Converttrack] Captain LLM sync failed: #{e.message}")
end
