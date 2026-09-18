# frozen_string_literal: true

module Converttrack
  class DemoConversationBuilder
    PRIORITY_MAP = {
      'urgent' => :urgent,
      'high' => :high,
      'medium' => :medium,
      'low' => :low
    }.freeze

    def initialize(account:, inboxes:, agents:, scenarios:, message_variants:, demo_user: nil, assistant: nil)
      @account = account
      @inboxes = inboxes
      @agents = agents
      @demo_user = demo_user
      @scenarios = scenarios
      @message_variants = message_variants
      @assistant = assistant
    end

    def create_conversation(contact:, layer:, started_at:, scenario: nil, resolve: nil, assign_agent: true)
      scenario ||= @scenarios.sample
      inbox = select_inbox(scenario)
      assignee = assign_agent ? pick_assignee(layer) : nil
      resolve = infer_resolve(layer) if resolve.nil?

      contact_inbox = find_or_create_contact_inbox(contact, inbox)
      conversation = contact_inbox.conversations.create!(
        account: @account,
        inbox: inbox,
        contact: contact,
        assignee: assignee,
        priority: PRIORITY_MAP[scenario['priority']] || :medium,
        status: :open,
        created_at: started_at,
        updated_at: started_at
      )

      seed_messages(conversation, scenario, assignee, layer, started_at)

      apply_labels(conversation, scenario)
      finalize_conversation(conversation, started_at, resolve)
      update_contact_activity(contact, conversation)
      conversation
    end

    private

    def select_inbox(scenario)
      key = scenario['inbox'].presence || %w[whatsapp email sms web].sample
      @inboxes.fetch(key.to_sym) || @inboxes.values.sample
    end

    def find_or_create_contact_inbox(contact, inbox)
      contact_inbox = inbox.contact_inboxes.find_by(contact: contact)
      return contact_inbox if contact_inbox

      source_id = contact_inbox_source_id(contact, inbox)
      inbox.contact_inboxes.find_or_create_by!(contact: contact, source_id: source_id)
    end

    def contact_inbox_source_id(contact, inbox)
      case inbox.channel_type
      when 'Channel::Whatsapp', 'Channel::Sms'
        contact.phone_number.to_s.delete_prefix('+').presence || rand(10**10..10**15).to_s
      when 'Channel::Email'
        contact.email.presence || "demo-#{SecureRandom.hex(4)}@demo-client.fr"
      else
        SecureRandom.hex(12)
      end
    end

    def infer_resolve(layer)
      case layer
      when :historical then rand < 0.7
      when :recent then rand < 0.55
      else false
      end
    end

    def pick_assignee(layer)
      return @agents.sample if @demo_user.blank?

      case layer
      when :live
        rand < 0.75 ? @demo_user : @agents.sample
      else
        roll = rand
        if roll < 0.45
          @demo_user
        elsif roll < 0.8
          @agents.sample
        end
      end
    end

    def message_senders
      [@demo_user, *@agents].compact.uniq
    end

    def seed_messages(conversation, scenario, assignee, layer, started_at)
      messages = scenario['messages'] || []
      messages = build_fallback_messages if messages.empty?

      current_time = started_at
      messages.each_with_index do |entry, index|
        current_time += message_delay(layer, index, entry['type']) unless index.zero?
        create_message_at(conversation, entry, assignee, current_time)
      end

      append_live_variants(conversation, current_time) if layer == :live && rand < 0.4
    end

    def build_fallback_messages
      [
        { 'type' => 'incoming', 'content' => @message_variants.dig('incoming')&.sample || 'Bonjour' },
        { 'type' => 'private', 'content' => 'ConvertTrack IA - intent: info, pipeline: nouveau' },
        { 'type' => 'outgoing', 'sender' => 'agent', 'content' => @message_variants.dig('outgoing')&.sample || 'Bonjour !' }
      ]
    end

    def message_delay(layer, index, type)
      case layer
      when :live
        return 0.seconds if index.zero?

        type == 'private' ? rand(2..8).seconds : rand(30.seconds..8.minutes)
      when :recent
        type == 'private' ? rand(2..10).seconds : rand(1.minute..45.minutes)
      else
        type == 'private' ? rand(2..15).seconds : rand(5.minutes..4.hours)
      end
    end

    def create_message_at(conversation, entry, assignee, at)
      case entry['type']
      when 'incoming'
        conversation.messages.create!(
          account: @account,
          inbox: conversation.inbox,
          message_type: :incoming,
          content: entry['content'],
          sender: conversation.contact,
          created_at: at,
          updated_at: at
        )
      when 'private'
        sender = entry['sender'] == 'agent' ? (assignee || message_senders.sample) : (assignee || @demo_user || @agents.first)
        conversation.messages.create!(
          account: @account,
          inbox: conversation.inbox,
          message_type: :outgoing,
          private: true,
          content: entry['content'],
          sender: sender,
          created_at: at,
          updated_at: at
        )
      when 'outgoing'
        sender = outgoing_sender(entry, assignee)
        message = conversation.messages.create!(
          account: @account,
          inbox: conversation.inbox,
          message_type: :outgoing,
          private: false,
          content: entry['content'],
          sender: sender,
          created_at: at,
          updated_at: at
        )
        trigger_reply_event(message, conversation, at)
        message
      end
    end

    def outgoing_sender(entry, assignee)
      if entry['sender'] == 'captain' && @assistant
        @assistant
      else
        assignee || message_senders.sample
      end
    end

    def append_live_variants(conversation, current_time)
      at = current_time + rand(1.minute..5.minutes)
      conversation.messages.create!(
        account: @account,
        inbox: conversation.inbox,
        message_type: :incoming,
        content: @message_variants.dig('incoming')&.sample || 'Merci pour votre reponse.',
        sender: conversation.contact,
        created_at: at,
        updated_at: at
      )

      return if rand < 0.25

      at = at + rand(2.minutes..10.minutes)
      agent = conversation.assignee || message_senders.sample
      message = conversation.messages.create!(
        account: @account,
        inbox: conversation.inbox,
        message_type: :outgoing,
        content: @message_variants.dig('outgoing')&.sample || 'Avec plaisir !',
        sender: agent,
        created_at: at,
        updated_at: at
      )
      trigger_reply_event(message, conversation, at)
    end

    def apply_labels(conversation, scenario)
      labels = Array(scenario['labels']).compact
      conversation.update_labels(labels) if labels.any?
    end

    def finalize_conversation(conversation, started_at, resolve)
      return unless resolve

      resolution_at = started_at + rand(30.minutes..24.hours)
      conversation.update_columns(status: Conversation.statuses[:resolved], updated_at: resolution_at) # rubocop:disable Rails/SkipsModelValidations
      ReportingEventListener.instance.conversation_resolved(
        Events::Base.new('conversation_resolved', resolution_at, { conversation: conversation })
      )
    rescue StandardError
      nil
    end

    def update_contact_activity(contact, conversation)
      last_at = conversation.messages.maximum(:created_at) || conversation.created_at
      contact.update_columns(last_activity_at: last_at, updated_at: last_at) # rubocop:disable Rails/SkipsModelValidations
    end

    def trigger_reply_event(message, conversation, at)
      waiting_since = conversation.messages.where(message_type: :incoming).where('created_at <= ?', at).last&.created_at || conversation.created_at
      ReportingEventListener.instance.reply_created(
        Events::Base.new('reply_created', at, {
                           message: message,
                           conversation: conversation,
                           waiting_since: waiting_since
                         })
      )
    rescue StandardError
      nil
    end
  end
end
