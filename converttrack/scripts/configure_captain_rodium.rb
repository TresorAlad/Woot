# frozen_string_literal: true

require Rails.root.join('lib/converttrack/configure_captain_llm')

result = Converttrack::ConfigureCaptainLlm.perform!

if result[:configured]
  puts "[converttrack] Captain LLM configure: #{result[:model]} @ #{result[:endpoint]}"
  puts '[converttrack] Redemarrez rails et sidekiq pour appliquer la config Agents SDK.'
else
  puts "[converttrack] Captain LLM non configure: #{result[:reason]}"
  exit 1
end
