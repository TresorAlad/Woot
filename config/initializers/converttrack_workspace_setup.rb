# frozen_string_literal: true

Rails.application.config.to_prepare do
  Account.class_eval do
    after_create_commit :converttrack_setup_workspace, if: :converttrack_auto_setup?
    after_update_commit :converttrack_sync_after_settings_change, if: :converttrack_auto_setup?

    private

    def converttrack_auto_setup?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('CONVERTTRACK_AUTO_SETUP', true))
    end

    def resolved_workspace_type
      (settings || {})['converttrack_workspace_type'].presence ||
        custom_attributes&.dig('converttrack_workspace_type').presence ||
        'custom'
    end

    def converttrack_setup_workspace
      Converttrack::WorkspaceSetup.setup_account!(self, workspace_type: resolved_workspace_type)
    rescue StandardError => e
      Rails.logger.error("[Converttrack] Workspace setup failed for account #{id}: #{e.message}")
    end

    def converttrack_sync_after_settings_change
      return unless saved_change_to_settings?

      keys = %w[converttrack_automation_mode converttrack_workspace_type converttrack_catalog_sources]
      return unless keys.any? { |key| settings_before_last_save&.dig(key) != settings&.dig(key) }

      Converttrack::WorkspaceSetup.refresh_account_tokens_map!
      Converttrack::WorkspaceSetup.notify_converttrack!(self, workspace_type: resolved_workspace_type)
    rescue StandardError => e
      Rails.logger.warn("[Converttrack] Settings sync failed for account #{id}: #{e.message}")
    end
  end
end
