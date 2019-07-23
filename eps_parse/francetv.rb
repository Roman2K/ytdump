require 'nokogiri'
require_relative '../item'

module EpsParse

class FranceTV
  def min_duration; 20 * 60 end

  # https://www.france.tv/france-2/fort-boyard/
  def playlist_items(url)
    uri = URI(url).tap do |u|
      u.host.sub(/^www\./, "") == "france.tv" && u.path.split("/").size == 3 \
        or return
    end
    html = EpsParse.request_get!(uri).body
    episodes_from_html(html, uri)
  end

  def episodes_from_html(html, uri)
    Nokogiri::HTML.parse(html).
      css(".c-program__head-slider .c-card-video__textarea").
      map { |el|
        ep_uri = el.css("a:first").first&.[](:href).
          tap { |path| path or raise "episode link not found" }.
          yield_self { |path| uri.dup.tap { |u| u.path = path } }
        id = ep_uri.path.split("/").fetch(-1)[%r{(\d+)-}, 1] \
          or raise "ID not found in URL"

        Item.new \
          idx: id.to_i,
          id: id,
          title: el.css(".c-card-video__description").first.
            tap { |s| s or raise "title not found" }.
            text.strip,
          duration: el.css(".c-metadata-list").first&.text \
            &.[](/(\d+) min\b/, 1).
            tap { |n| n or raise "duration not found" }.
            to_i * 60,
          url: ep_uri.to_s
      }
  end
end

end # EpsParse
