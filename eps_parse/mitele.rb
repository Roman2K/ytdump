require 'json'
require 'date'

module EpsParse

class Mitele < Parser
  CHECK = [
    "https://www.mitele.es/programas-tv/first-dates/",
    -> n { n >= 10 },
  ]

  def min_duration; 20 * 60 end

  # https://www.mitele.es/programas-tv/ven-a-cenar-conmigo/1505720681723/
  def uri_ok?(uri)
    uri.host.sub(/^www\./, "") == "mitele.es" or return false
    cs = uri.path.split("/")
    cs[0,2] == ["", "programas-tv"] && cs.size == 3
  end

  def episodes_from_doc(doc, uri)
    doc.css("script[type='text/javascript']").
      to_a.grep(/\bcontainer_mtweb\s*=/) { $' }.
      first.tap { |s| s or raise "mtweb data not found" }.
      yield_self { |s| JSON.parse s }.
      fetch("container").fetch("tabs").
      select { |tab|
        %w[automatic-list navigation].include?(tab.fetch("type")) \
          && tab["contents"]
      }.flat_map { |tab|
        eps = {}.tap do |all|
          seasons_done = Set.new
          add_children = -> els, titles=[] do
            els.each do |el|
              if el.key? "children"
                add_children.call \
                  el.fetch("children"),
                  [*titles, el.fetch("title")]
              else
                case el.fetch("info").fetch("type") 
                when 'episode'
                  all[el.fetch("id")] ||= el.merge("_parent_titles" => titles)
                when 'season'
                  id = el.fetch("id")
                  next if seasons_done.include? id
                  seasons_done << id
                  add_children.(get_season_eps(el))
                else
                  raise "unhandled episode type"
                end
              end
            end
          end
          add_children.(tab.fetch("contents"))
        end
        eps.values.map do |ep|
          Item.new \
            id: ep.fetch("id"),
            idx: ep.fetch("info").fetch("episode_number"),
            title: \
              [ spanish_date(get_date(ep)),
                *ep.fetch("_parent_titles"),
                ep.fetch("title"),
                ep.fetch("subtitle") ].join(" - "),
            url: \
              uri.dup.tap { |u|
                u.path = ep.fetch("images").fetch("thumbnail").fetch("href")
              }.to_s,
            duration: ep.fetch("info").fetch("duration")
        end
      }
  end

  module URIEncode
    URL_RE = Regexp.union %w[ . - ]
    def self.encode(s)
      URI.encode_www_form_component(s)
    end
    def self.encode_url(s)
      encode(s).gsub(URL_RE) { '%%%X' % $&.ord }
    end
  end

  private def get_season_eps(el)
    url = el.fetch("link").fetch("href")
    url = "www.mitele.es#{url}"
    url = "/tabs/mtweb?url=#{URIEncode.encode_url url}&tabId=34124.0"
    url = "https://mab.mediaset.es/1.0.0/get?oid=bitban" \
      "&eid=#{URIEncode.encode url}"
    JSON.parse(EpsParse.request_get!(URI url).body).fetch "contents"
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
