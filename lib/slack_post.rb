class SlackPost
  GREY    = "#e8e8e8"
  RED     = "#d72b3f"
  YELLOW  = "#ffc965"
  GREEN   = "#36a64f"

  def initialize(message, attachments = [])
    @_message = message
    @_attachments = attachments
  end

  def post!
    post_to_slack(message, attachments)
  rescue => e
    msg = "I'm sorry, but something went wrong. Please try again!"
    post_to_slack(msg, [
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

  def post_to_slack(message, attachments)
    slack_client.chat_postMessage(channel: CONFIG.slack_channel, text: message, attachments: JSON.dump(attachments))
  end

  def slack_client
    @_slack_client ||= Slack::Web::Client.new.tap(&:auth_test)
  end
end
