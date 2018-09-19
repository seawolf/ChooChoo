require 'ostruct'
require 'yaml'

module Config
  module_function

  def parse(hash)
    OpenStruct.new(hash.each_with_object({}) do |(key, val), memo|
      memo[key] = val.is_a?(Hash) ? Config.parse(val) : val
    end)
  end
end

CONFIG = Config.parse(YAML.load_file('./config.yml'))

require 'slack'
Slack.configure do |slack|
  slack.token = CONFIG.slack_token
end
