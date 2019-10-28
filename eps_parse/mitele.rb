require 'json'
require 'date'

module EpsParse

class Mitele < Parser
  CHECK = [
    "https://www.mitele.es/programas-tv/first-dates/0000000024966/",
    -> n { n >= 19 },
  ]

  def min_duration; 20 * 60 end

  # https://www.mitele.es/programas-tv/ven-a-cenar-conmigo/1505720681723/
  def uri_ok?(uri)
    uri.host.sub(/^www\./, "") == "mitele.es" or return false
    cs = uri.path.split("/")
    cs[0,2] == ["", "programas-tv"] && cs.size == 4
  end

  def episodes_from_doc(doc, uri)
    doc.css("script[type='text/javascript']").
      to_a.grep(/\bcontainer_mtweb\s*=/) { $' }.
      first.tap { |s| s or return [] }.
      yield_self { |s| JSON.parse s }.
      fetch("container").fetch("tabs").
      find { |t| t.fetch("filter") == "_pt_programa" }.
      tap { |t| t or raise "tab data not found" }.
      fetch("contents").
      flat_map { |tab| tab.fetch("children").map { |ep|
        Item.new \
          id: ep.fetch("id"),
          idx: ep.fetch("info").fetch("episode_number"),
          title: "%s - %s" % [spanish_date(get_date(ep)), ep.fetch("title")],
          url: uri.dup.tap { |u| u.path = ep.fetch("link").fetch("href") }.to_s,
          duration: ep.fetch("info").fetch("duration")
      } }
  end

  ES_FMT = "%02d-%s-%04d (%s)".freeze
  ES_WDAYS = %w( lun mar mié jue vie sáb dom ).freeze
  ES_MOS = %w( ene feb mar abr may jun jul ago sep oct nov dic ).freeze

  private def spanish_date(d)
    ES_FMT % [d.day, ES_MOS.fetch(d.month-1), d.year, ES_WDAYS.fetch(d.wday-1)]
  end

  private def get_date(ep)
    inf = ep.fetch "info"
    ymd = (s = inf.fetch("synopsis")[%r%(\d{2})/(\d{2})/(\d{4})%]) \
      ? s.split("/").reverse
      : inf.fetch("creation_date").split("-")
    ymd.map! &:to_i
    ymd.size == 3 && (1900...3000) === ymd[0] or raise "invalid date format"
    Date.new *ymd
  end
end

end # EpsParse
