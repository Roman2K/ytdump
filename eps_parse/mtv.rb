require 'json'

module EpsParse

class MTV < Parser
  def uri_ok?(uri)
    uri.host.sub(/^www\./, "") == "mtv.com" or return false
    cs = uri.path.split("/")
    cs[0,2] == ["", "shows"] && cs.last == "episode-guide" \
      && cs.size == 4 && uri.query.nil? \
  end

  def episodes_from_doc(doc, uri)
    feed_uri = doc.
      css("[data-tffeed]:first").first&.[](:"data-tffeed").
      tap { |u| u or raise "feed element not found" }.
      yield_self { |u| URI u }

    fetch_eps feed_uri
  end

  private def fetch_eps(uri)
    items = []
    loop do
      res = JSON.parse EpsParse.request_get!(uri).body
      res.fetch("status").fetch("text") == "OK" \
        or raise "unexpected result status"
      res = res.fetch "result"
      res.fetch("data").fetch("items").each do |i|
        next if i["isAd"]
        date = Time.at(i.fetch("airDate").to_i)
        items << Item.new(
          idx: i.fetch("season").fetch("episodeNumber").to_i,
          id: i.fetch("id"),
          title: [
            date.strftime("%Y-%m-%d"), i.fetch("number"), i.fetch("title")
          ].join(" - "),
          duration: i.fetch("duration"),
          url: i.fetch("canonicalURL")
        )
      end
      if s = res["nextPageURL"]
        uri = URI s
      else
        params = Hash[URI.decode_www_form uri.query || ""]
        season = params["season"] and season > "1" or break
        params["season"] = (season.to_i - 1).to_s
        params["pageNumber"] = "1"
        prev = uri
        uri = uri.dup.tap { |u| u.query = URI.encode_www_form params }
      end
    end
    items
  end
end

end # EpsParse
