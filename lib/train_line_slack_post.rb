class TrainLineSlackPost
  def initialize(is_morning_commute=true, budge=0)
    @_is_morning_commute = is_morning_commute
    @_datetime = Time.now + budge.minutes

    header = "Hello! Here's how your #{is_morning_commute? ? 'morning' : 'evening'} commute looks today:"
    messages = attachments.map do |data|
      attachment_for_data(data)
    end

    messages << filtering_warning if filtering_warning

    @_slack_post = SlackPost.new(header, messages).tap(&:post!)
  end

  private

  def is_morning_commute?
    @_is_morning_commute
  end

  def datetime
    @_datetime
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

  def attachments
    @_attachments ||= begin
      (is_morning_commute? ? CONFIG.routes.morning : CONFIG.routes.evening).inject([]) do |attachments, line|
        args = { at: line['at'], from: line['from'], to: line['to'], datetime: datetime }.keep_if {|k, v| v.present? }
        attachments << TrainLine.new(args)
      end
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

  def filtering_warning
    warning = attachments.first&.filtering_warning
    if warning
      {
          "fallback": warning,
          "color": SlackPost::RED,
          "title": "Warning",
          "text": warning,
          "footer": "Powered by <http://www.realtimetrains.co.uk|Realtime Trains>",
          "ts": datetime.to_i
      }
    end
  end

  def attachment_colour_for_data(data)
    if data.no_services?
      SlackPost::GREY
    elsif data.cancellations? || data.heavy_delays?
      SlackPost::RED
    elsif data.light_delays?
      SlackPost::YELLOW
    else # data.no_delays?
      SlackPost::GREEN
    end
  end
end
