class Train
  def initialize(uid:, at_crs: nil, datetime: Time.now)
    @_uid       = uid
    @_at_crs    = at_crs
    @_datetime  = datetime
  end

  def datetime
    @_datetime
  end

  def request_info
    if no_service?
      return "#{uid} on #{datetime.strftime("%d/%m/%Y")}"
    end

    station_at    = result[:location]
    time_at       = result[:scheduled]
    station_to    = result[:destination]

    "#{time_at} #{station_at} to #{station_to}"
  end

  def cancellation
    result[:cancellation]
  end

  def delay_mins
    result[:delay_mins].to_i
  end

  def no_service?
    result.empty?
  end

  def cancelled?
    !no_service? && result[:cancellation].presence
  end
  def heavily_delayed?
    !no_service? && result[:delay_mins].to_i > CONFIG.delays.high
  end
  def lightly_delayed?
    !no_service? && result[:delay_mins].to_i > CONFIG.delays.low
  end
  def not_delayed?
    !cancelled? &&
        !heavily_delayed? &&
        !lightly_delayed?
  end

  private

  def uid
    @_uid
  end

  def at_crs
    @_at_crs
  end

  def api_call
    @_api_call ||= ApiCall.for(CONFIG.rtt_api_base, url, basic_auth: {
        username: CONFIG.rtt_api_username, password: CONFIG.rtt_api_password
    })
  end

  def url
    "/json/service/#{uid}/#{datetime.year.pad(4)}/#{datetime.month.pad}/#{datetime.day.pad}"
  end

  def result
    @_result ||= begin
      srv = api_call.body

      return {} unless srv['serviceUid'].to_s == uid

      headcode    = srv['runningIdentity']
      operator    = srv['atocName']
      origin      = srv['origin'].map do |origin|
        origin['description']
      end.literate_join

      destination = srv['destination'].map do |destination|
        destination['description']
      end.literate_join

      locations   = srv.fetch('locations', [])
      location    = at_crs ? locations.find do |location|
        location['crs'] == at_crs
      end : locations.first || srv['origin'].first

      scheduled   = location['gbttBookedDeparture'] || location['workingTime']
      actual      = location['realtimeDeparture'] || location['workingTime']

      scheduled   = datetime.change(hour: scheduled[0..1], min: scheduled[2..3])
      actual      = datetime.change(hour: actual[0..1], min: actual[2..3])

      delay_mins  = (actual.to_i - scheduled.to_i) / 60
      canx        = location['cancelReasonLongText'].presence

      {
          headcode:     headcode,
          operator:     operator,
          origin:       origin,
          location:     location['description'],
          destination:  destination,
          scheduled:    scheduled.strftime("%H:%M"),
          actual:       actual.strftime("%H:%M"),
          delay_mins:   delay_mins,
          cancellation: canx
      }
    end
  end
end
