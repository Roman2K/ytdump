require 'time'

module EpsParse

class AnabolicTV < Parser
  # https://anabolictv.com/channels/team3cc-bostin-loyd
  def uri_ok?(uri)
    uri.host.sub(/^www\./, "") == "anabolictv.com" or return false
    cs = uri.path.split("/")
    cs[0,2] == ["", "channels"] && cs.size == 3 && uri.query.nil?
  end

  def episodes_from_doc(doc, uri)
    doc.css(".cactus-post-item:has(.cactus-post-title.h4)").map do |el|
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
    end
  end
end

end # EpsParse
