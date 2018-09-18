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
    attachments = (morning_commute ? [
        TrainLine.new('FTN', from: 'GLD', datetime: datetime), # Waterloo-Guildford-Portsmouth
        TrainLine.new('FTN', from: 'BTN', datetime: datetime), # Brighton-Portsmouth
        TrainLine.new('FTN', from: 'VIC', datetime: datetime), # Victoria-Portsmouth
        TrainLine.new('FTN', from: 'LIT', datetime: datetime), # Littlehampton-Portsmouth
        TrainLine.new('FTN', from: 'ESL', datetime: datetime), # Waterloo-Eastleigh-Portsmouth
        TrainLine.new('FTN', to:   'HAV', datetime: datetime), # Portsmouth-Havant
    ] : [
        TrainLine.new('HAV', from: 'GLD', to: 'FTN', datetime: datetime), # Waterloo-Guildford-Portsmouth
        TrainLine.new('HAV', from: 'BTN', to: 'FTN', datetime: datetime), # Brighton-Portsmouth
        TrainLine.new('HAV', from: 'VIC', to: 'FTN', datetime: datetime), # Victoria-Portsmouth
        TrainLine.new('HAV', from: 'LIT', to: 'FTN', datetime: datetime), # Littlehampton-Portsmouth
    ]).map do |data|
      attachment_for_data(data)
    end

    @post = post_to_slack(message: header, attachments: attachments)
  rescue => e
    msg = "I'm sorry, but something went wrong. Please try again!"
    @post = post_to_slack(message: msg, attachments: [
        {
            "fallback": e.message,
            "color": "#d72b3f",
            "title": 'Error',
            "text": e.message,
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

    strs << "Services by #{data.summary_data[:zero].literate_join} are running to time." if data.summary_data[:zero].any?

    strs << "Services by #{data.summary_data[:low].literate_join} are running without significant delay." if data.summary_data[:low].any?

    data.summary_data[:high].group_by do |high_entry|
      high_entry[:avg_delay_mins]
    end.tap do |delayed_operators_grouped|
      delayed_operators_grouped.keys.sort.reverse.each do |avg_delay_mins|
        delayed_operators = delayed_operators_grouped[avg_delay_mins]
        strs << "Services from #{delayed_operators.collect {|operator| operator[:operator] }.literate_join} are running with an average delay of #{avg_delay_mins} minutes."
      end
    end

    strs.join("\n")
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
    if data.heavy_delays?
      "#d72b3f"
    elsif data.light_delays?
      "#ffc965"
    else # data.no_delays?
      "#36a64f"
    end
  end
end

class TrainLine
  def initialize(at, from: nil, to: nil, datetime: Time.now)
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

    str = "Querying for train services at #{station_at}"
    str << ", from #{station_from}" if station_from
    str << ", to #{station_to}" if station_to
    str.strip!
    str << ":"

    str[0] = str[0].upcase

    str
  end

  def heavy_delays?
    summary_data[:high].any?
  end
  def light_delays?
    summary_data[:high].none? &&
    summary_data[:low].any?
  end
  def no_delays?
    summary_data[:high].none? &&
    summary_data[:low].none?
    # summary_data[:zero].any?
  end

  def summary_data
    @_summary_data ||= begin
      groups = { zero: [], low:  [], high: [] }
      memo = results.inject(groups) do |memo, (operator, services)|
        avg_delay_mins = services.sum {|srv| srv[:delay_mins]} / services.count

        if avg_delay_mins < 3
          memo[:zero] << operator
        elsif avg_delay_mins <= 5
          memo[:low] << operator
        else
          memo[:high] << { operator: operator, avg_delay_mins: avg_delay_mins }
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

      {
          headcode:     headcode,
          operator:     operator,
          origin:       origin,
          destination:  destination,
          scheduled:    scheduled,
          actual:       actual,
          delay_mins:   delay_mins
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
