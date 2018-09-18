require 'yaml'
require 'slack'

CONFIG = OpenStruct.new(YAML.load_file('./config.yml'))

Slack.configure do |slack|
  slack.token = CONFIG.slack_token
end

SLACK_CHANNEL     = CONFIG.slack_channel
RTT_API_USERNAME  = CONFIG.rtt_api_username
RTT_API_PASSWORD  = CONFIG.rtt_api_password
RTT_API_BASE      = CONFIG.rtt_api_base
RTT_API_PREFIX    = CONFIG.rtt_api_prefix

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
    slack_client.chat_postMessage(channel: SLACK_CHANNEL, text: message, attachments: JSON.dump(attachments))
  end

  def slack_client
    @_slack_client ||= Slack::Web::Client.new.tap(&:auth_test)
  end

  def summary_for_data(data)
    strs = []


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
    (is_morning_commute ? CONFIG.morning : CONFIG.evening).inject([]) do |attachments, line|
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
    if data.cancellations? || data.heavy_delays?
      "#d72b3f"
    elsif data.light_delays?
      "#ffc965"
    else # data.no_delays?
      "#36a64f"
    end
  end
end

class TrainLine
  def initialize(at:, from: nil, to: nil, datetime: Time.now)
    @_from_crs = from
    @_at_crs   = at
    @_to_crs   = to
    @_datetime = datetime

    puts filtering_warning if filtering_warning
  end

  def datetime
    @_datetime
  end

  def request_info
    station_from  = api_call.body.fetch('filter', {}).fetch('origin', {})['name']
    station_at    = api_call.body['location']['name']
    station_to    = api_call.body.fetch('filter', {}).fetch('destination', {})['name']

    [ station_from, station_at, station_to ].reject(&:blank?).join(" - ")
  end

  def cancellations?
    summary_data[:cancellations].any?
  end
  def heavy_delays?
    summary_data[:high].any?
  end
  def light_delays?
    summary_data[:low].any?
  end
  def no_delays?
    !cancellations? &&
    !heavy_delays? &&
    !light_delays?
  end

  def summary_data
    @_summary_data ||= begin
      groups = { cancellations: [], zero: [], low: [], high: [] }
      memo = results.inject(groups) do |memo, (operator, services)|
        cancellations = services.map {|srv| srv[:cancellation] }.compact
        avg_delay_mins = services.sum {|srv| srv[:delay_mins]} / services.count

        if cancellations.any?
          memo[:cancellations] << { operator: operator, cancellations: cancellations }
        elsif avg_delay_mins > 5
          memo[:high] << { operator: operator, avg_delay_mins: avg_delay_mins }
        elsif avg_delay_mins > 3
          memo[:low] << operator
        elsif avg_delay_mins <= 3
          memo[:zero] << operator
        end

        memo
      end
    end
  end

  private

  def api_call
    @_api_call ||= ApiCall.for(RTT_API_BASE, url, basic_auth: { username: RTT_API_USERNAME, password: RTT_API_PASSWORD })
  end

  def from_crs
    @_from_crs
  end
  def at_crs
    @_at_crs
  end
  def to_crs
    @_to_crs
  end

  def url
    "/json/search/#{url_crs_section}/#{datetime.year.pad(4)}/#{datetime.month.pad}/#{datetime.day.pad}/#{datetime.hour.pad}#{datetime.min.pad}"
  end

  def url_crs_section
    str = "#{at_crs}"
    str << "/from/#{from_crs}"  if from_crs
    str << "/to/#{to_crs}"      if to_crs
    str
  end

  def filtering_warning
    "Sorry, we can't currently support filtering services by previous or later calling points if they ran over a day ago." if
        datetime < (Time.now - 1.day) && (from_crs || to_crs)
  end

  def results
    @_results ||= api_call.body.fetch('services', []).map do |srv|
      next unless srv['locationDetail']['realtimeDeparture']

      headcode    = srv['runningIdentity']
      operator    = srv['atocName']
      origin      = srv['locationDetail']['origin'].map do |origin|
          origin['description']
      end.literate_join

      destination = srv['locationDetail']['destination'].map do |destination|
          destination['description']
      end.literate_join

      scheduled   = srv['locationDetail']['gbttBookedDeparture']
      actual      = srv['locationDetail']['realtimeDeparture']
      scheduled   = datetime.change(hour: scheduled[0..1], min: scheduled[2..3])
      actual      = datetime.change(hour: actual[0..1], min: actual[2..3])

      delay_mins  = (actual.to_i - scheduled.to_i) / 60
      canx        = srv['locationDetail']['cancelReasonLongText'].presence

      {
          headcode:     headcode,
          operator:     operator,
          origin:       origin,
          destination:  destination,
          scheduled:    scheduled,
          actual:       actual,
          delay_mins:   delay_mins,
          cancellation: canx
      }
    end.compact.sort_by do |srv|
      srv[:scheduled]
    end.group_by do |srv|
      srv[:operator]
    end
  end
end

class Train
  def initialize(trainline, journey_headcode)
  end
end

module ApiCall
  module_function

  def for(url_base, path, query: {}, basic_auth: nil)
    Faraday.new(url: url_base) do |faraday|
      faraday.response :json
      faraday.basic_auth(basic_auth[:username], basic_auth[:password]) if basic_auth
      faraday.adapter Faraday.default_adapter
    end.get("#{RTT_API_PREFIX}#{path}", query)
  end
end

class Fixnum
  def pad(num=2)
    to_s.rjust(num, '0')
  end
end

class Array
  def literate_join(separator: ', ', last_separator: 'and', oxford_comma: false)
    return join if length < 2
    "#{self[0..-2].join(separator)}#{oxford_comma ? ',' : ''} #{last_separator} #{self[-1]}"
  end
end

if ARGV.include?('--morning')
  SlackPost.new(true, 15)
elsif ARGV.include?('--evening')
  SlackPost.new(false, 15)
end
