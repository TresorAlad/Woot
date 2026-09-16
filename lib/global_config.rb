class GlobalConfig
  VERSION = 'V1'.freeze
  KEY_PREFIX = 'GLOBAL_CONFIG'.freeze
  DEFAULT_EXPIRY = 1.day

  class << self
    def get(*args)
      config_keys = args.flatten.map(&:to_s).uniq
      return {}.with_indifferent_access if config_keys.empty?

      cache_keys = config_keys.map { |key| cache_key_for(key) }
      cached_values = fetch_from_cache_batch(cache_keys)

      config = {}
      missing_keys = []

      config_keys.each_with_index do |config_key, index|
        cached_value = cached_values[index]
        if cached_value.present?
          config[config_key] = JSON.parse(cached_value)['value']
        else
          missing_keys << config_key
        end
      end

      if missing_keys.any?
        db_values = fetch_from_db_batch(missing_keys)
        cache_writes = {}

        missing_keys.each do |config_key|
          value_from_db = db_values[config_key]
          cache_writes[cache_key_for(config_key)] = { value: value_from_db }.to_json
          config[config_key] = value_from_db
        end

        write_to_cache_batch(cache_writes)
      end

      typecast_config(config)
      config.with_indifferent_access
    end

    def get_value(arg)
      get(arg)[arg]
    end

    def clear_cache(config_key = nil)
      if config_key.present?
        Redis::Alfred.delete(cache_key_for(config_key))
        return
      end

      Redis::Alfred.scan_each(match: "#{VERSION}:#{KEY_PREFIX}:*") do |key|
        Redis::Alfred.delete(key)
      end
    end

    private

    def cache_key_for(config_key)
      "#{VERSION}:#{KEY_PREFIX}:#{config_key}"
    end

    def general_configs
      @general_configs ||= ConfigLoader.new.general_configs
    end

    def fetch_from_cache_batch(cache_keys)
      $alfred.with { |conn| conn.mget(*cache_keys) }
    end

    def fetch_from_db_batch(config_keys)
      values = {}
      InstallationConfig.unscoped.where(name: config_keys).order(created_at: :desc).find_each do |record|
        values[record.name] ||= record.value
      end
      values
    end

    def write_to_cache_batch(cache_writes)
      $alfred.with do |conn|
        conn.pipelined do |pipeline|
          cache_writes.each do |key, value|
            pipeline.set(key, value, ex: DEFAULT_EXPIRY.to_i)
          end
        end
      end
    end

    def typecast_config(config)
      config.each do |config_key, config_value|
        config_type = general_configs.find { |c| c['name'] == config_key }&.dig('type')
        config[config_key] = ActiveRecord::Type::Boolean.new.cast(config_value) if config_type == 'boolean'
      end
    end
  end
end
