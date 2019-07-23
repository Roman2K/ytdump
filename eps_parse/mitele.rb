require 'nokogiri'
require 'json'
require_relative '../item'

module EpsParse

class Mitele
  def min_duration; 20 * 60 end

  # https://www.mitele.es/programas-tv/ven-a-cenar-conmigo/1505720681723/
  def playlist_items(url)
    uri = URI(url).tap do |u|
      u.host.sub(/^www\./, "") == "mitele.es" or return
      cs = u.path.split("/")
      cs[0,2] == ["", "programas-tv"] && cs.size == 4 or return
    end
    html = EpsParse.request_get!(uri).body
    episodes_from_html(html, uri)
  end

  def episodes_from_html(html, uri)
    Nokogiri::HTML.parse(html).css("script[type='text/javascript']").
      to_a.grep(/\bcontainer_mtweb\s*=/) { $' }.
      first.tap { |s| s or raise "metadata not found" }.
      yield_self { |s| JSON.parse s }.
      fetch("container").fetch("tabs").
      find { |t| t.fetch("filter") == "_pt_programa" }.
      tap { |t| t or raise "tab data not found" }.
      fetch("contents").
      flat_map { |tab| tab.fetch("children").map { |ep|
        Item.new \
          id: ep.fetch("id"),
          idx: ep.fetch("info").fetch("episode_number"),
          title: ep.fetch("title"),
          url: uri.dup.tap { |u| u.path = ep.fetch("link").fetch("href") }.to_s,
          duration: ep.fetch("info").fetch("duration")
      } }
  end
end

end # EpsParse
