require 'nokogiri'
require_relative '../item'

module EpsParse

class InvalidURIError < StandardError; end

class Parser
  Item = ::Item

  def self.doc(html)
    Nokogiri::HTML.parse html
  end

  def min_duration; end
  protected def html_uri(uri); uri end

  def playlist_items(uri)
    uri = URI uri
    uri_ok? uri or raise InvalidURIError
    html = EpsParse.request_get!(html_uri uri).body
    episodes_from_html html, uri
  end

  def episodes_from_html(html, uri)
    episodes_from_doc self.class.doc(html), uri
  end

  def name
    self.class.name.split("::").last
  end

  def check(log)
    if !defined?(self.class::CHECK)
      log.warn "no ::CHECK"
      return true
    end
    url, count = self.class::CHECK
    log[url: url].info "starting"
    items = begin
      playlist_items(url)
    rescue => err
      log[err: err].error "exception in playlist_items()"
      return false
    end
    unless items
      log.error "unsupported URL"
      return false
    end
    found = items.size
    log[found: found].info "finished"
    count === found
  end
end

end # EpsParse
