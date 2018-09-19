class SlackPost
  def initialize(message, attachments)
    @_message = message
    @_attachments = attachments
  end

  def post!
    @post = post_to_slack
  rescue => e
    msg = "I'm sorry, but something went wrong. Please try again!"
    @post = post_to_slack(message: msg, attachments: [
        {
            "fallback": e.message,
            "color": "#d72b3f",
            "title": e.message,
            "text": "```#{e.backtrace.join("\n")}```",
            "mrkdwn": true,
            "ts": Time.now.to_i
        }
    ])
  end

  private

  def message
    @_message
  end

  def attachments
    @_attachments
  end

  def post_to_slack(message: message, attachments: [])
    slack_client.chat_postMessage(channel: CONFIG.slack_channel, text: message, attachments: JSON.dump(attachments))
  end

  def slack_client
    @_slack_client ||= Slack::Web::Client.new.tap(&:auth_test)
  end
end
