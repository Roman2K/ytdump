require 'nokogiri'
require 'time'
require_relative 'eps_parse'
require_relative 'item'

class AnabolicTV
  def min_duration; end

  # https://anabolictv.com/channels/team3cc-bostin-loyd
  def playlist_items(url)
    uri = URI(url).tap do |u|
      u.host.sub(/^www\./, "") == "anabolictv.com" or return
      cs = u.path.split("/")
      cs[0,2] == ["", "channels"] && cs.size == 3 && u.query.nil? or return
    end
    html = EpsParse.request_get!(uri).body
    episodes_from_html(html, uri)
  end

  def episodes_from_html(html, uri)
    Nokogiri::HTML.parse(html).
      css(".cactus-post-item:has(.cactus-post-title.h4)").
      map { |el|
        id = el.css("time").first&.[](:datetime).
          tap { |t| t or raise "time not found" }.
          yield_self { |t| Time.parse t }.
          strftime("%Y%m%d%H%M%S")
        Item.new \
          idx: id.to_i,
          id: id,
          url: el.css("a:first").first&.[](:href).
            tap { |u| u or raise "URL not found" }.
            tap { |u| u =~ /^https?:/ or raise "unexpected URL format" },
          title: el.css(".cactus-post-title").first.
            tap { |e| e or raise "title not found" }.
            text.strip
      }
  end
end
