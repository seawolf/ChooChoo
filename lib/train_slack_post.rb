class TrainSlackPost
  def initialize(is_morning_commute=true, budge=0)
    @_is_morning_commute = is_morning_commute
    @_datetime = Time.now + budge.minutes

    header = "Hello! Here's are your specific services on your #{is_morning_commute? ? 'morning' : 'evening'} commute today:"
    messages = attachments.map do |data|
      attachment_for_data(data)
    end

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
    if data.no_service?
      "This service is not scheduled to run."
    elsif data.cancelled?
      "This service is cancelled due to #{data.cancellation}."
    elsif data.heavily_delayed?
      "This service is running with a delay of #{data.delay_mins} minutes."
    elsif data.lightly_delayed?
      "This service is running without significant delay."
    else # data.not_delayed?
      "This service is running to time."
    end
  end

  def attachments
    @_attachments ||= begin
      location = is_morning_commute? ? CONFIG.journeys.morning_station : CONFIG.journeys.evening_station
      (is_morning_commute? ? CONFIG.journeys.morning : CONFIG.journeys.evening).inject([]) do |attachments, journey|
        journey = journey["dep"] if journey.is_a?(Hash)
        args = { uid: journey, at_crs: location, datetime: datetime }
        attachments << Train.new(args)
      end
    end
  end

  def attachment_for_data(data)
    {
        "fallback": [ data.request_info, summary_for_data(data) ].join("\n"),
        "color": attachment_colour_for_data(data),
        "title": data.request_info,
        "text": summary_for_data(data)
    }
  end

  def attachment_colour_for_data(data)
    if data.no_service?
      SlackPost::GREY
    elsif data.cancelled? || data.heavily_delayed?
      SlackPost::RED
    elsif data.lightly_delayed?
      SlackPost::YELLOW
    else # data.not_delayed??
      SlackPost::GREEN
    end
  end
end
