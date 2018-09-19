require 'ostruct'
require 'yaml'
CONFIG = OpenStruct.new(YAML.load_file('./config.yml'))

require 'slack'
Slack.configure do |slack|
  slack.token = CONFIG.slack_token
end
