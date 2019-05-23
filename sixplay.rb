require 'net/http'
require 'nokogiri'

module SixPlay
  def self.get_playlist_items(url)
    uri = URI url
    uri.host.sub(/^www\./, "") == "6play.fr" && uri.path.split("/").size == 2 \
      or return
    resp = Net::HTTP.get_response uri
    resp.kind_of? Net::HTTPSuccess or raise "unexpected response: %p" % resp
    html = resp.body.tap { |s| s.force_encoding Encoding::UTF_8 }
    episodes_from_html(html, uri).map &:playlist_item
  end

  def self.episodes_from_html(html, uri)
    string_doc(html).css("a").each_with_object([]) { |a, arr|
      ep = ep_from_el(a, uri) or next
      arr << ep
    }.tap { |eps|
      raise "no episodes found" if eps.empty?
    }
  end

  def self.ep_from_el(el, uri)
    ep = Ep.new

    # Duration
    ep.duration = el.css(".tile__duration").first.yield_self do |dur_el|
      dur_el or return
      parse_duration dur_el.text
    end

    # URL
    href = el[:href] or return
    ep.uri = uri.dup.tap { |u| u.path = href; u.query = nil }

    # ID
    path_prefix = "#{uri.path}/"
    href.start_with? path_prefix or return
    rest = href[path_prefix.size..-1]
    ep.id = rest[/\-c_(\d+)\b/, 1] or return

    # Number
    ep.num = (EpNum.from_url(rest) || EpNum.new).tap do |num|
      if !num.complete? \
        and text = el.css("h2").first&.text \
        and title_num = EpNum.from_title(text)
      then
        num.merge! title_num
      end
      if num.e && !num.complete? \
        and title_num = season_num(el)
      then
        num.merge! title_num
      end
      num.e or return
    end

    ep
  end

  def self.season_num(el)
    while el.respond_to?(:parent) && el = el.parent
      s = el.css("h2").first&.text \
        and num = EpNum.from_title(s) and num.s \
        and return num
    end
  end

  def self.file_doc(path)
    string_doc File.read path
  end

  def self.string_doc(s)
    Nokogiri::HTML.parse s
  end

  def self.parse_duration(s)
    min = 0
    until s.empty?
      min +=
        case s
        when /^(\d+)h */ then $1.to_i * 3600
        when /^(\d+)min */ then $1.to_i * 60
        when /^(\d+)s */ then $1.to_i
        else raise "unrecognized string: %p" % s
        end
      s = $'
    end
    min
  end

  Ep = Struct.new :id, :num, :uri, :duration do
    def playlist_item
      Item[id.to_i, id, uri.to_s, num.to_s]
    end
  end

  EpNum = Struct.new :s, :e, :name do
    def self.from_url(s)
      # /moundir-et-les-apprentis-aventuriers-p_5848/saison-4-episode-6-c_12373263
      # /les-princes-et-les-princesses-de-lamour-p_3442/episode-1-12-c_12220049
      s =~ /\bepisode-+(\d+)(?:-((?:-?\d+)+))?/i
      e, name = $1, $2
      s, e = [s[/\bsaison-+(\d+)/i, 1], e].map { |n| n&.to_i }
      self[s, e, name] if s || e
    end

    def self.from_title(s)
      # Saison 4 / Épisode 6
      s, e =
        [ s[/\bSaison +(\d+)/i, 1],
          s[/\b[EÉ]pisode +(\d+)/i, 1] ].map { |n| n&.to_i }
      self[s, e] if s || e
    end

    def complete?
      s && e
    end

    def merge!(x)
      self.s ||= x.s
      self.e ||= x.e
      self
    end

    def to_s
      e or raise "missing episode number"
      ("S%02dE%02d" % [s || 0, e]).tap do |s|
        s << "-#{name}" if name
      end
    end
  end
end
