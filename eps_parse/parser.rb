require 'nokogiri'
require_relative '../item'

module EpsParse

class Parser
  Item = ::Item

  def self.doc(html)
    Nokogiri::HTML.parse html
  end

  def min_duration; end

  def playlist_items(url)
    uri = URI url
    uri_ok? uri or return
    html = EpsParse.request_get!(uri).body
    episodes_from_html html, uri
  end

  def episodes_from_html(html, uri)
    episodes_from_doc self.class.doc(html), uri
  end
end

end # EpsParse
