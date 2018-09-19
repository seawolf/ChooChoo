module ApiCall
  module_function

  def for(url_base, path, query: {}, basic_auth: nil)
    Faraday.new(url: url_base) do |faraday|
      faraday.response :json
      faraday.basic_auth(basic_auth[:username], basic_auth[:password]) if basic_auth
      faraday.adapter Faraday.default_adapter
    end.get("#{CONFIG.rtt_api_prefix}#{path}", query)
  end
end
