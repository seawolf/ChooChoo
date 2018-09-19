class Fixnum
  def pad(num=2)
    to_s.rjust(num, '0')
  end
end
