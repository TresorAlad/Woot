# frozen_string_literal: true

require 'faker'
require 'json'
require 'yaml'
require 'active_support/testing/time_helpers'
require_relative 'captain_knowledge_seeder'
require_relative 'demo_conversation_builder'
require Rails.root.join('lib/seeders/reports/assistant_conversation_creator')

module Converttrack
  class DemoSeeder # rubocop:disable Metrics/ClassLength
    include ActiveSupport::Testing::TimeHelpers
    DEMO_EMAIL_DOMAIN = '@demo.converttrack.local'
    DEMO_CLIENT_DOMAIN = '@demo-client.fr'
    DEMO_TEAMS = %w[support ventes marketing].freeze
    TOTAL_CONTACTS = 100
    CLASSIFIED_CONVERSATIONS = 500
    ASSISTANT_CONVERSATIONS = 200
    CONVERTTRACK_LABELS = WorkspaceSetup::LABELS.map { |item| item[:title] }.freeze

    def self.perform!(email: ENV.fetch('CONVERTTRACK_DEMO_EMAIL', 'admin@techmentor.dev'))
      new(email: email).perform!
    end

    def initialize(email:)
      @email = email.to_s.downcase
      @data = YAML.safe_load(Rails.root.join('lib/converttrack/demo_data.yml').read)
      @teams = {}
      @agents = []
      @inboxes = {}
      @contacts = []
      @assistant = nil
      @demo_user = nil
    end

    def perform!
      validate!
      @account, @demo_user = find_account!
      puts "[converttrack-demo] Compte cible: #{@account.name} (##{@account.id}) - #{@email}"

      with_seed_performance_mode do
        clear_demo_data!
        ensure_converttrack_labels!
        create_teams!
        create_agents!
        create_mock_inboxes!
        ensure_demo_user_access!
        configure_demo_settings!
        create_captain_assistant!
        create_custom_attributes!
        create_contacts!
        create_contact_notes!
        create_classified_conversations!
        create_assistant_conversations!
        create_campaigns!
        write_federation_json!
        write_campaign_runs_json!
      end

      puts '[converttrack-demo] Seed demo termine.'
    end

    private

    def validate!
      if Rails.env.production? && ENV['CONVERTTRACK_DEMO_SEED'] != 'true'
        raise 'CONVERTTRACK_DEMO_SEED=true requis en production'
      end

      raise 'Email demo invalide' if @email.blank?
    end

    def refresh_db_connection!
      ActiveRecord::Base.connection_pool.release_connection
      ActiveRecord::Base.connection.verify!
    rescue StandardError
      ActiveRecord::Base.establish_connection
    end

    def with_seed_performance_mode
      original_adapter = ActiveJob::Base.queue_adapter
      original_job_logger = ActiveJob::Base.logger
      original_rails_logger = Rails.logger
      connection = ActiveRecord::Base.connection
      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.logger = Logger.new(File::NULL)
      Rails.logger.level = Logger::WARN
      connection.execute('SET statement_timeout TO 0')
      yield
    ensure
      ActiveJob::Base.queue_adapter = original_adapter
      ActiveJob::Base.logger = original_job_logger
      Rails.logger.level = original_rails_logger.level if original_rails_logger
      ActiveRecord::Base.connection.execute('RESET statement_timeout')
    end

    def find_account!
      user = User.find_by!(email: @email)
      membership = user.account_users.find_by(role: :administrator)
      raise "Aucun compte admin pour #{@email}" unless membership

      [membership.account, user]
    end

    def ensure_demo_user_access!
      @inboxes.each_value do |inbox|
        InboxMember.find_or_create_by!(inbox: inbox, user: @demo_user)
      end

      Array(@data['teams']).first(2).each do |team_name|
        team = @teams[team_name]
        next unless team

        TeamMember.find_or_create_by!(team: team, user: @demo_user)
      end
    end

    def internal_inbox_id
      @account.settings['converttrack_demo_inbox_id'].to_i
    end

    def clear_demo_data! # rubocop:disable Metrics/AbcSize
      puts '[converttrack-demo] Nettoyage des donnees demo...'

      clear_captain_data!
      clear_conversations_bulk!
      clear_contacts_bulk!
      @account.campaigns.delete_all

      demo_users = User.where('email LIKE ?', "%#{DEMO_EMAIL_DOMAIN}")
      demo_user_ids = demo_users.pluck(:id)
      @account.account_users.where(user_id: demo_user_ids).destroy_all
      NotificationSetting.where(account_id: @account.id, user_id: demo_user_ids).delete_all
      TeamMember.where(user_id: demo_user_ids).destroy_all
      InboxMember.where(user_id: demo_user_ids).destroy_all

      @account.inboxes.where.not(id: internal_inbox_id).find_each(&:destroy) if internal_inbox_id.positive?
      @account.inboxes.where.not('name LIKE ?', '%ConvertTrack Demo%').find_each(&:destroy) if internal_inbox_id.zero?

      @account.teams.where('LOWER(name) IN (?)', DEMO_TEAMS).destroy_all
    end

    def clear_captain_data!
      assistant_ids = @account.captain_assistants.where(name: 'ConvertTrack Copilot').pluck(:id)
      return if assistant_ids.empty?

      ConversationOutcome.where(account_id: @account.id).delete_all if defined?(ConversationOutcome)
      Captain::AssistantResponse.by_account(@account.id).where(assistant_id: assistant_ids).delete_all
      Captain::Document.for_account(@account.id).where(assistant_id: assistant_ids).delete_all
      CaptainInbox.where(captain_assistant_id: assistant_ids).delete_all
      Captain::Assistant.where(id: assistant_ids).delete_all
    end

    def clear_conversations_bulk!
      @account.conversations.pluck(:id).each_slice(500) do |batch|
        Message.where(conversation_id: batch).delete_all
        ReportingEvent.where(conversation_id: batch).delete_all
        AutomationRulePendingExecution.where(conversation_id: batch).delete_all
        Mention.where(conversation_id: batch).delete_all
        ConversationParticipant.where(conversation_id: batch).delete_all
        ActsAsTaggableOn::Tagging.where(taggable_type: 'Conversation', taggable_id: batch).delete_all
        ConversationOutcome.where(conversation_id: batch).delete_all if defined?(ConversationOutcome)
        Notification.where(primary_actor_type: 'Conversation', primary_actor_id: batch).delete_all
        CsatSurveyResponse.where(conversation_id: batch).delete_all
        Conversation.where(id: batch).delete_all
      end
    end

    def clear_contacts_bulk!
      contact_ids = @account.contacts.pluck(:id)
      return if contact_ids.empty?

      ContactInbox.where(contact_id: contact_ids).delete_all
      Note.where(contact_id: contact_ids).delete_all
      ActsAsTaggableOn::Tagging.where(taggable_type: 'Contact', taggable_id: contact_ids).delete_all
      Contact.where(id: contact_ids).delete_all
    end

    def ensure_converttrack_labels!
      WorkspaceSetup.ensure_labels!(@account)
    end

    def create_teams!
      Array(@data['teams']).each do |name|
        @teams[name] = @account.teams.find_or_create_by!(name: name)
      end
    end

    def create_agents!
      Array(@data['agents']).each do |agent_data|
        user = User.find_by(email: agent_data['email'])
        unless user
          user = User.new(
            name: agent_data['name'],
            email: agent_data['email'],
            password: "Password1!.#{SecureRandom.hex(8)}",
            confirmed_at: Time.current
          )
          user.skip_confirmation!
          user.save!
        end
        membership = AccountUser.find_or_initialize_by(account: @account, user: user)
        membership.role = :agent
        membership.save!
        Array(agent_data['teams']).each do |team_name|
          next unless @teams[team_name]

          TeamMember.find_or_create_by!(team: @teams[team_name], user: user)
        end
        @agents << user
      end
    end

    def create_mock_inboxes!
      domain = 'demo.converttrack.local'

      @inboxes[:whatsapp] = create_whatsapp_inbox("Demo WhatsApp")
      @inboxes[:email] = create_email_inbox("Demo Email", domain)
      @inboxes[:sms] = create_sms_inbox("Demo SMS")
      @inboxes[:web] = create_web_inbox("Demo Site Web", 'http://127.0.0.1:5000/test')

      @inboxes.each_value do |inbox|
        InboxMember.find_or_create_by!(inbox: inbox, user: @demo_user)
        @agents.each { |agent| InboxMember.find_or_create_by!(inbox: inbox, user: agent) }
      end
    end

    def create_whatsapp_inbox(name)
      phone = unique_whatsapp_phone
      Channel::Whatsapp.insert({ account_id: @account.id, phone_number: phone, created_at: Time.current, updated_at: Time.current }) # rubocop:disable Rails/SkipsModelValidations
      channel = Channel::Whatsapp.find_by!(phone_number: phone)
      @account.inboxes.create!(name: name, channel: channel)
    end

    def unique_whatsapp_phone
      loop do
        phone = "+225#{rand(10_000_000..99_999_999)}"
        return phone unless Channel::Whatsapp.exists?(phone_number: phone)
      end
    end

    def create_email_inbox(name, domain)
      suffix = SecureRandom.hex(4)
      channel = Channel::Email.create!(
        account: @account,
        email: "demo-#{suffix}@#{domain}",
        forward_to_email: "fwd-#{suffix}@#{domain}"
      )
      @account.inboxes.create!(name: name, channel: channel)
    end

    def create_sms_inbox(name)
      channel = Channel::Sms.create!(account: @account, phone_number: "+225#{rand(10_000_000..99_999_999)}")
      @account.inboxes.create!(name: name, channel: channel)
    end

    def create_web_inbox(name, url)
      channel = Channel::WebWidget.create!(account: @account, website_url: url, widget_color: '#1f93ff')
      @account.inboxes.create!(name: name, channel: channel)
    end

    def create_custom_attributes!
      Array(@data['custom_attributes']).each do |attr|
        definition = @account.custom_attribute_definitions.find_or_initialize_by(
          attribute_key: attr['key'],
          attribute_model: :contact_attribute
        )
        definition.attribute_display_name = attr['display_name']
        definition.attribute_display_type = attr['display_type']
        definition.attribute_values = attr['values'] if attr['values']
        definition.save!
      end
    end

    def create_contacts!
      detailed = Array(@data['contacts'])
      detailed.each { |row| @contacts << create_contact_from_row(row) }

      remaining = TOTAL_CONTACTS - @contacts.size
      remaining.times { @contacts << create_generated_contact }
      puts "[converttrack-demo] #{@contacts.size} contacts crees"
    end

    def create_contact_from_row(row)
      created_at = pick_contact_created_at(row)
      contact = @account.contacts.create!(
        name: row['name'],
        email: row['email'],
        phone_number: row['phone_number'],
        contact_type: row['contact_type'] || 'lead',
        additional_attributes: {
          city: row['city'],
          country: row['country'],
          country_code: row['country_code'],
          company_name: row['company']
        }.compact,
        custom_attributes: {
          produit_interet: row['produit_interet'],
          budget: row['budget'],
          canal_acquisition: row['canal_acquisition'],
          statut_client: row['statut_client']
        }.compact
      )
      contact.update_columns(created_at: created_at, updated_at: created_at) # rubocop:disable Rails/SkipsModelValidations
      contact.add_labels(Array(row['labels']))
      link_contact_inboxes(contact, Array(row['inboxes']))
      contact
    end

    def create_generated_contact
      cities = [
        { city: 'Abidjan', country: 'Cote d Ivoire', country_code: 'CI', phone_prefix: '+225' },
        { city: 'Dakar', country: 'Senegal', country_code: 'SN', phone_prefix: '+221' },
        { city: 'Paris', country: 'France', country_code: 'FR', phone_prefix: '+33' }
      ]
      loc = cities.sample
      type = %w[lead lead lead customer visitor].sample
      created_at = rand(90.days.ago..Time.current)

      contact = @account.contacts.create!(
        name: Faker::Name.name,
        email: "client-#{SecureRandom.hex(4)}#{DEMO_CLIENT_DOMAIN}",
        phone_number: "#{loc[:phone_prefix]}#{rand(10_000_000..99_999_999)}",
        contact_type: type,
        additional_attributes: { city: loc[:city], country: loc[:country], country_code: loc[:country_code] }
      )
      contact.update_columns(created_at: created_at, updated_at: created_at) # rubocop:disable Rails/SkipsModelValidations
      if rand < 0.7
        contact.update!(
          custom_attributes: {
            produit_interet: %w[Canape Oslo Table Natura Bureau Ergo].sample,
            budget: "#{rand(50..300)} 000 FCFA",
            canal_acquisition: %w[WhatsApp Site web Email SMS].sample,
            statut_client: %w[Prospect Client actif A relancer].sample
          }
        )
      end
      pipeline = %w[pipeline-interet pipeline-prix pipeline-relance pipeline-converti pipeline-nouveau].sample
      contact.add_labels([pipeline])
      link_contact_inboxes(contact, inbox_keys_for_type)
      contact
    end

    def pick_contact_created_at(row)
      return rand(90.days.ago..30.days.ago) if row['federation']
      return rand(30.days.ago..1.day.ago) if row['contact_type'] == 'lead'

      rand(90.days.ago..Time.current)
    end

    def inbox_keys_for_type
      keys = %w[whatsapp email sms web]
      keys.sample(rand(1..3))
    end

    def link_contact_inboxes(contact, keys)
      mapping = { 'whatsapp' => :whatsapp, 'email' => :email, 'sms' => :sms, 'web' => :web }
      keys.each do |key|
        inbox = @inboxes[mapping[key.to_s]]
        next unless inbox

        source_id = contact_inbox_source_id(contact, inbox)
        inbox.contact_inboxes.find_or_create_by!(contact: contact, source_id: source_id)
      end
    end

    def contact_inbox_source_id(contact, inbox)
      case inbox.channel_type
      when 'Channel::Whatsapp', 'Channel::Sms'
        contact.phone_number.to_s.delete_prefix('+').presence || rand(10**10..10**15).to_s
      when 'Channel::Email'
        contact.email.presence || "demo-#{SecureRandom.hex(4)}#{DEMO_CLIENT_DOMAIN}"
      else
        SecureRandom.hex(12)
      end
    end

    def create_contact_notes!
      @contacts.sample(30).each do |contact|
        Note.create!(
          account: @account,
          contact: contact,
          user: @demo_user,
          content: "Note demo: #{Faker::Lorem.sentence(word_count: 8)}"
        )
      end

      Array(@data['contacts']).each do |row|
        next if row['note'].blank?

        contact = @contacts.find { |item| item.email == row['email'] }
        next unless contact

        Note.create!(account: @account, contact: contact, user: @demo_user, content: row['note'])
      end
    end

    def create_classified_conversations!
      builder = DemoConversationBuilder.new(
        account: @account,
        inboxes: @inboxes,
        agents: @agents,
        demo_user: @demo_user,
        scenarios: @data['scenarios'],
        message_variants: @data['message_variants'] || {},
        assistant: @assistant
      )

      CLASSIFIED_CONVERSATIONS.times do |index|
        refresh_db_connection! if (index % 25).zero?
        layer, started_at = conversation_layer(index, CLASSIFIED_CONVERSATIONS)
        contact = @contacts.sample
        scenario = @data['scenarios'][index % @data['scenarios'].size]
        builder.create_conversation(contact: contact, layer: layer, started_at: started_at, scenario: scenario)
        print "\r[converttrack-demo] Conversations: #{index + 1}/#{CLASSIFIED_CONVERSATIONS}"
      end
      puts
    end

    def conversation_layer(index, total)
      if index < (total * 0.6).to_i
        [:historical, rand(90.days.ago..7.days.ago)]
      elsif index < (total * 0.85).to_i
        [:recent, rand(7.days.ago..1.day.ago)]
      else
        [:live, Time.current - rand(5.minutes..4.hours)]
      end
    end

    def create_captain_assistant!
      web_inbox = @inboxes[:web]
      @assistant = Captain::Assistant.create!(
        account: @account,
        name: 'ConvertTrack Copilot',
        description: 'Assistant demo ConvertTrack pour le site web.',
        config: { feature_faq: true, feature_memory: true, product_name: @account.name }
      )
      CaptainInbox.create!(captain_assistant: @assistant, inbox: web_inbox)
      CaptainKnowledgeSeeder.seed!(account: @account, assistant: @assistant)
    end

    def create_assistant_conversations!
      creator = Seeders::Reports::AssistantConversationCreator.new(
        account: @account,
        assistant: @assistant,
        inbox: @inboxes[:web],
        resources: { contacts: @contacts, agents: [@demo_user, *@agents] }
      )

      outcomes = assistant_outcome_distribution
      outcomes.each_with_index do |outcome, index|
        refresh_db_connection! if (index % 25).zero?
        layer, created_at = assistant_layer(index, outcomes.size)
        creator.create_conversation(created_at: created_at, outcome: outcome)
        print "\r[converttrack-demo] Captain conversations: #{index + 1}/#{outcomes.size}"
      end
      puts
    end

    def assistant_layer(index, total)
      if index < (total * 0.6).to_i
        [:historical, rand(30.days.ago..7.days.ago)]
      elsif index < (total * 0.85).to_i
        [:recent, rand(7.days.ago..1.day.ago)]
      else
        [:live, Time.current - rand(5.minutes..3.hours)]
      end
    end

    def assistant_outcome_distribution
      counts = {
        resolved_by_assistant: (ASSISTANT_CONVERSATIONS * 0.4).round,
        handled_by_both: (ASSISTANT_CONVERSATIONS * 0.25).round,
        handed_off: (ASSISTANT_CONVERSATIONS * 0.2).round,
        resolved_and_reopened: (ASSISTANT_CONVERSATIONS * 0.15).round
      }
      outcomes = counts.flat_map { |outcome, count| Array.new(count, outcome) }
      outcomes.shuffle
    end

    def create_campaigns!
      label_map = @account.labels.index_by(&:title)
      Array(@data['campaigns']).each do |campaign_data|
        inbox_key = campaign_data['inbox'].to_sym
        inbox = @inboxes[inbox_key]
        next unless inbox

        audience = Array(campaign_data['audience_labels']).filter_map do |title|
          label = label_map[title]
          { 'type' => 'Label', 'id' => label.id } if label
        end

        attrs = {
          account: @account,
          inbox: inbox,
          title: campaign_data['title'],
          message: campaign_data['message'],
          campaign_type: campaign_data['campaign_type'],
          campaign_status: campaign_data['campaign_status'],
          enabled: true,
          audience: audience
        }
        attrs[:trigger_rules] = { 'url' => campaign_data['trigger_url'] } if campaign_data['trigger_url'].present?
        attrs[:scheduled_at] = 2.days.ago if campaign_data['campaign_type'] == 'one_off'

        @account.campaigns.create!(attrs)
      end
    end

    def write_federation_json!
      path = ENV.fetch('FEDERATION_STORE_PATH', '/shared/federated_contacts.json')
      data = {}
      federation_contacts = @contacts.select { |c| c.email.to_s.include?('demo-client.fr') }.first(3)

      federation_contacts.each do |contact|
        key = (contact.email.presence || contact.phone_number).to_s.downcase
        conversations = contact.conversations.order(:created_at).limit(8)
        timeline = conversations.map do |conversation|
          {
            account_id: @account.id,
            conversation_id: conversation.id,
            intent: conversation.label_list.first,
            pipeline_stage: conversation.label_list.find { |l| l.start_with?('pipeline-') },
            content_preview: conversation.messages.where(message_type: :incoming).last&.content.to_s.truncate(120),
            recorded_at: conversation.created_at.iso8601
          }
        end

        data[key] = {
          contact_key: key,
          account_contacts: {
            @account.id.to_s => {
              contact_id: contact.id,
              conversation_id: conversations.last&.id
            }
          },
          timeline: timeline
        }
      end

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(data))
    end

    def write_campaign_runs_json!
      path = ENV.fetch('CAMPAIGN_RUNS_PATH', '/shared/campaign_runs.json')
      runs = @account.campaigns.map do |campaign|
        {
          id: SecureRandom.uuid,
          account_id: @account.id,
          name: campaign.title,
          message: campaign.message,
          audience: { labels: campaign.audience.filter_map { |item| item['id'] } },
          channels: [{
            type: campaign_channel_type(campaign.inbox),
            inbox_id: campaign.inbox_id,
            status: campaign.completed? ? 'queued' : 'pending',
            campaign_id: campaign.id
          }],
          status: campaign.completed? ? 'queued' : 'processing',
          created_at: campaign.created_at.iso8601
        }
      end

      payload = { @account.id.to_s => runs }
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(payload))
    end

    def campaign_channel_type(inbox)
      {
        'Channel::Sms' => 'sms',
        'Channel::WebWidget' => 'website',
        'Channel::Whatsapp' => 'whatsapp',
        'Channel::Email' => 'email'
      }.fetch(inbox.channel_type, 'sms')
    end

    def configure_demo_settings!
      @account.enable_features!('captain_integration', 'captain_integration_v2')
      settings = @account.settings || {}
      settings['converttrack_automation_mode'] = 'hybrid'
      settings['converttrack_catalog_sources'] = [
        ENV.fetch('CONVERTTRACK_CATALOG_URL', 'http://127.0.0.1:3000/converttrack/demo_catalog.json')
      ]
      @account.update!(settings: settings)
    end
  end
end
