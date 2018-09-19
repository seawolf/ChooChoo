require_relative './lib/core_ext/array'
require_relative './lib/core_ext/fixnum'

require_relative './lib/config'

require_relative './lib/api_call'
require_relative './lib/slack_post'
require_relative './lib/train_line'

if ARGV.include?('--morning')
  SlackPost.new(true, 15)
elsif ARGV.include?('--evening')
  SlackPost.new(false, 15)
end
