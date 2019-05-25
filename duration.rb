module Duration
  def self.fmt(d)
    case
    when d < 60 then "%ds" % d
    when d < 3600 then m, d = d.divmod(60); "%dm%s" % [m, fmt(d)]
    when d < 86400 then h, d = d.divmod(3600); "%dh%s" % [h, fmt(d)]
    else ds, d = d.divmod(86400); "%dd%s" % [ds, fmt(d)]
    end.sub /([a-z])(0[a-z])+$/, '\1'
  end
end
