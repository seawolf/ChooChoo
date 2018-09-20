require_relative './lib/core_ext/array'
require_relative './lib/core_ext/fixnum'

require_relative './lib/config'

require_relative './lib/api_call'
require_relative './lib/slack_post'
require_relative './lib/train'
require_relative './lib/train_slack_post'
require_relative './lib/train_line'
require_relative './lib/train_line_slack_post'

if ARGV.include?('--morning')
  TrainLineSlackPost.new(true, 15)
  TrainSlackPost.new(true, 15) unless ARGV.include?('--summary-only')
end

if ARGV.include?('--evening')
  TrainLineSlackPost.new(false, 15)
  TrainSlackPost.new(false, 15) unless ARGV.include?('--summary-only')
end
