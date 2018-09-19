class TrainLine
  def initialize(at:, from: nil, to: nil, datetime: Time.now)
    @_from_crs = from
    @_at_crs   = at
    @_to_crs   = to
    @_datetime = datetime
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

  def filtering_warning
    "Sorry, we can't currently support filtering services by previous or later calling points if they ran over a day ago." if
        datetime < (Time.now - 1.day) && (from_crs || to_crs)
  end

  def no_services?
    summary_data[:none]
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
      groups = { none: results.empty?, cancellations: [], zero: [], low: [], high: [] }

      memo = results.inject(groups) do |memo, (operator, services)|
        cancellations = services.map {|srv| srv[:cancellation] }.compact
        avg_delay_mins = services.sum {|srv| srv[:delay_mins]} / services.count

        if cancellations.any?
          memo[:cancellations] << { operator: operator, cancellations: cancellations }
        elsif avg_delay_mins > CONFIG.delays.high
          memo[:high] << { operator: operator, avg_delay_mins: avg_delay_mins }
        elsif avg_delay_mins > CONFIG.delays.low
          memo[:low] << operator
        elsif avg_delay_mins <= CONFIG.delays.low
          memo[:zero] << operator
        end

        memo
      end
    end
  end

  private

  def api_call
    @_api_call ||= ApiCall.for(CONFIG.rtt_api_base, url, basic_auth: {
        username: CONFIG.rtt_api_username, password: CONFIG.rtt_api_password
    })
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

  def results
    @_results ||= api_call.body.fetch('services', nil).to_a.map do |srv|
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
