class SlackPost
  def initialize(is_morning_commute=true, budge=0)
    header = "Hello! Here's how your #{is_morning_commute ? 'morning' : 'evening'} commute looks today:"
    datetime = Time.now + budge.minutes
    attachments = attachments(is_morning_commute, datetime).map do |data|
      attachment_for_data(data)
    end

    @post = post_to_slack(message: header, attachments: attachments)
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

  def post_to_slack(message:, attachments: [])
    slack_client.chat_postMessage(channel: CONFIG.slack_channel, text: message, attachments: JSON.dump(attachments))
  end

  def slack_client
    @_slack_client ||= Slack::Web::Client.new.tap(&:auth_test)
  end

  def summary_for_data(data)
    strs = []

    strs << "There are no services scheduled." if data.summary_data[:none]

    data.summary_data[:cancellations].inject({}) do |cancellations, cancellations_entry|
      if cancellations_entry[:cancellations].any?
        cancellations[cancellations_entry[:operator]] ||= []
        cancellations[cancellations_entry[:operator]].concat(cancellations_entry[:cancellations])
        cancellations[cancellations_entry[:operator]].uniq!
      end
      cancellations
    end.tap do |cancellation_operators|
      cancellation_operators.each do |operator, cancellations|
        strs << "Services from #{operator} are experiencing cancellations due to #{cancellations.literate_join}." if cancellations.any?
      end
    end

    data.summary_data[:high].group_by do |high_entry|
      high_entry[:avg_delay_mins]
    end.tap do |delayed_operators_grouped|
      delayed_operators_grouped.keys.sort.reverse.each do |avg_delay_mins|
        delayed_operators = delayed_operators_grouped[avg_delay_mins]
        strs << "Services from #{delayed_operators.collect {|operator| operator[:operator] }.literate_join} are running with an average delay of #{avg_delay_mins} minutes."
      end
    end
    strs << "Services by #{data.summary_data[:low].literate_join} are running without significant delay." if data.summary_data[:low].any?

    strs << "Services by #{data.summary_data[:zero].literate_join} are running to time." if data.summary_data[:zero].any?

    strs.join("\n")
  end

  def attachments(is_morning_commute, datetime)
    (is_morning_commute ? CONFIG.routes.fetch(:morning) : CONFIG.routes.fetch(:evening)).inject([]) do |attachments, line|
      args = { at: line['at'], from: line['from'], to: line['to'], datetime: datetime }.keep_if {|k, v| v.present? }
      attachments << TrainLine.new(args)
    end
  end

  def attachment_for_data(data)
    {
        "fallback": [ data.request_info, summary_for_data(data) ].join("\n"),
        "color": attachment_colour_for_data(data),
        "title": data.request_info,
        "text": summary_for_data(data),
        "footer": "Powered by <http://www.realtimetrains.co.uk|Realtime Trains>",
        "ts": data.datetime.to_i
    }
  end

  def attachment_colour_for_data(data)
    if data.no_services?
      "#e8e8e8"
    elsif data.cancellations? || data.heavy_delays?
      "#d72b3f"
    elsif data.light_delays?
      "#ffc965"
    else # data.no_delays?
      "#36a64f"
    end
  end
end
