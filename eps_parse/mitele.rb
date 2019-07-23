require 'json'

module EpsParse

class Mitele < Parser
  def min_duration; 20 * 60 end

  # https://www.mitele.es/programas-tv/ven-a-cenar-conmigo/1505720681723/
  def uri_ok?(uri)
    uri.host.sub(/^www\./, "") == "mitele.es" or return false
    cs = uri.path.split("/")
    cs[0,2] == ["", "programas-tv"] && cs.size == 4
  end

  def episodes_from_doc(doc, uri)
    doc.css("script[type='text/javascript']").
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
