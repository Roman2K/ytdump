module EpsParse

class Telecinco < Parser
  CHECK = [
    "https://www.telecinco.es/la-isla-de-las-tentaciones/a-la-carta/",
    -> n { n >= 8 },
  ]

  def uri_ok?(uri)
    uri.host.sub(/^www\./, "") == "telecinco.es" or return false
    cs = uri.path.split("/")
    cs.last == "a-la-carta" && cs.size == 3
  end

  def playlist_items(uri)
    uri = URI uri
    page = 1
    items = []
    loop do
      its = super(uri)
      break if its.empty?
      items = its.concat items
      page += 1
      uri.query = URI.encode_www_form page: page
    end
    items
  end

  def episodes_from_doc(doc, uri)
    path_prefix = uri.path.chomp "a-la-carta/"
    doc.css("article a[href^='#{path_prefix}']").filter_map { |a|
      title = a.text.strip
      next if title.empty?  # could be a <img/>
      path = a["href"] or next
      path =~ /_(\d+)\.html$/ or next
      id = $1
      Item.new \
        id: id,
        idx: id.to_i,
        url: uri.dup.tap { |u| u.path = path; u.query = nil }.to_s,
        title: title
    }.reverse
  end
end

end
