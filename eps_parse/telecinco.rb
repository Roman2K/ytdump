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

  def episodes_from_doc(doc, uri)
    doc.css("a[href^='#{uri.path}']").filter_map { |a|
      path = a["href"] or next
      !a.text.empty? or next  # could be a <img/>
      path =~ /_(\d+)\.html$/ or next
      id = $1
      Item.new \
        id: id,
        idx: id.to_i,
        url: uri.dup.tap { _1.path = path }.to_s,
        title: a.text.strip
    }.reverse
  end
end

end
