class Array
  def literate_join(separator: ', ', last_separator: 'and', oxford_comma: false)
    return join if length < 2
    "#{self[0..-2].join(separator)}#{oxford_comma ? ',' : ''} #{last_separator} #{self[-1]}"
  end
end
