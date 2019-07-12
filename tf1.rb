require 'nokogiri'
require_relative 'eps_parse'
require_relative 'item'

class TF1
  def min_duration; 20 * 60 end

  # https://www.tf1.fr/tf1/ninja-warrior/videos/replay
  def episodes(url)
    uri = URI url
    uri.host.sub(/^www\./, "") == "tf1.fr" \
      && uri.path.split("/")[-2..-1] == %w( videos replay ) \
      or return
    resp = EpsParse.request_get! uri
    episodes_from_html resp.body, uri
  end

  def episodes_from_html(html, uri)
    Nokogiri::HTML.parse(html).css("[class^='VideoCard_card__box']").map do |el|
      ep_uri = el.css("a:first").first.yield_self do |e|
        path = e&.[](:href) or raise "URL element not found"
        path =~ %r{^/tf[x1]/} or raise "unexpected URL path: %p" % path
        uri.dup.tap { |u| u.path = path }
      end
      id = ep_uri.path[/\-(\d+)\.\w+$/, 1] or raise "ID not found"

      Ep.new Item.new \
        idx: id.to_i,
        id: id,
        url: ep_uri.to_s,
        duration: el.css("[class*='_duration_']").
          first.tap { |e| e or raise "duration not found" }.
          yield_self { |e| parse_duration e.text },
        title: \
          el.css(
            "[class*='_header_']:first" \
            ", [class*='_videoLabel_']:first"
          ).tap { |els|
            els.size == 2 or raise "header and/or description not found"
          }.map(&:text).join(" - ")
    end
  end

  Ep = Struct.new :playlist_item

  private def parse_duration(s)
    case s.strip
    when /^(\d+)m(\d+)?$/ then $1.to_i * 60 + $2.to_i
    when /^(\d+)h(\d+)?$/ then $1.to_i * 3600 + $2.to_i * 60
    else raise "unhandled duration format: %p" % s
    end
  end
end
