# frozen_string_literal: true

assistant = Captain::Assistant.find_by(id: ENV.fetch('ASSISTANT_ID', 1))
raise 'Assistant introuvable' unless assistant

puts "[test] model=#{InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value}"
puts "[test] endpoint=#{InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value}"

runner = Captain::Assistant::AgentRunnerService.new(
  assistant: assistant,
  run_options: Captain::Assistant::AgentRunnerService::RunOptions.new(source: 'playground')
)

result = runner.generate_response(message_history: [{ role: 'user', content: 'salut' }])

if result['error'].present?
  puts "[test] ERREUR: #{result.inspect}"
  exit 1
end

puts "[test] OK: #{result['response'].to_s[0..400]}"
puts "[test] keys: #{result.keys.join(', ')}"
