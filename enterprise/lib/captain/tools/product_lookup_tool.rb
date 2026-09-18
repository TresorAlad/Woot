require 'net/http'
require 'json'

class Captain::Tools::ProductLookupTool < Captain::Tools::BasePublicTool
  description 'Search connected product catalogs for price, availability, and delivery information'
  param :query, type: 'string', desc: 'Product name, SKU, or customer question about a product'

  def perform(tool_context, query:)
    log_tool_usage('product_lookup', { query: query })

    sources = catalog_sources
    return 'No product catalog configured for this workspace.' if sources.empty?

    results = sources.filter_map { |source| fetch_catalog(source, query) }
    return "No product match found for: #{query}" if results.empty?

    results.join("\n---\n")
  end

  private

  def safe_to_run_after_new_customer_message?
    true
  end

  def catalog_sources
    settings = @assistant.account.settings || {}
    Array(settings['converttrack_catalog_sources']).select(&:present?)
  end

  def fetch_catalog(source, query)
    uri = URI(source)
    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    body = JSON.parse(response.body)
    items = body.is_a?(Array) ? body : Array(body['products'] || body['items'])
    matches = items.select do |item|
      haystack = [item['name'], item['sku'], item['title'], item['description']].compact.join(' ').downcase
      haystack.include?(query.downcase)
    end
    return nil if matches.empty?

    matches.first(3).map { |item| format_product(item) }.join("\n")
  rescue StandardError => e
    Rails.logger.warn("[Captain] Product lookup failed for #{source}: #{e.message}")
    nil
  end

  def format_product(item)
    <<~PRODUCT.strip
      Product: #{item['name'] || item['title']}
      SKU: #{item['sku'] || 'n/a'}
      Price: #{item['price'] || 'n/a'}
      Availability: #{item['availability'] || item['stock'] || 'n/a'}
      Delivery: #{item['delivery_days'] || item['delivery'] || 'n/a'}
    PRODUCT
  end
end
