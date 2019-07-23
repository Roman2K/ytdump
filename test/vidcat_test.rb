$:.unshift __dir__ + "/.."
require 'minitest/autorun'
require 'vidcat'

class VidCatTest < Minitest::Test
  TMP_SUFFIX = ".out"

  def test_cat
    test_cat_out %w(
      a.ogg
      b.mkv
      b.fr.srt
      b.scc
      c.mp4
    ), merge: [
      %w( b.mkv b.fr.srt b.scc ),
    ], concat: [
      %w( b.out.mkv c.mp4 ),
    ], final: %w(
      a.ogg
      b.mkv
    )

    test_cat_out %w(
      a.mkv
      a.fr.srt
      b.mkv
      b.fr.srt
    ), merge: [
      %w( a.mkv a.fr.srt ),
      %w( b.mkv b.fr.srt ),
    ], concat: [
      %w( a.out.mkv b.out.mkv ),
    ], final: %w(
      a.mkv
    )

    test_cat_out %w(
      a01.mkv
      a02.mkv
    ),
      merge: [],
      concat: [%w( a01.mkv a02.mkv )],
      final: %w( a.mkv ),
      opts: {basename: -> s { s.sub /\d+$/, "" }}

    test_cat_out %w(
      a01.mp4
      a01.fr.srt
    ),
      merge: [%w( a01.mp4 a01.fr.srt )],
      concat: [],
      final: %w( a.mkv ),
      opts: {basename: -> s { s.sub /\d+$/, "" }}

    test_cat_out %w(
      a.mkv
    ),
      merge: [],
      concat: [],
      final: %w( a.mkv )

    test_cat_out %w(
      a.mkv
      x.ogg
    ),
      merge: [],
      concat: [],
      final: %w( b.mkv b.ogg ),
      opts: {basename: -> s { "b" }}

    test_cat_out %w(
      a.mkv
      b.mp4
    ),
      merge: [],
      concat: [%w( a.mkv b.mp4 )],
      final: %w( a.mkv )

    test_cat_out %w(
      a.ogg
      b.scc
    ),
      merge: [],
      concat: [],
      final: %w( a.ogg b.scc )
  end

  private def test_cat_out(*args, &block)
    Dir.mktmpdir do |dir|
      Dir.chdir dir do
        do_test_cat_out *args, &block
      end
    end
  end

  private def do_test_cat_out(infiles, merge: [], concat: [], final: [],
    opts: {}
  )
    cat = VidCat.new tmp_suffix: TMP_SUFFIX, **opts

    pathnames = -> arr { arr.map { |f| Pathname f } }
    %i( infiles final ).each { |var| eval "#{var} = pathnames[#{var}]" }
    %i( merge concat ).each { |var| eval "#{var} = #{var}.map &pathnames" }

    infiles.each { |f| FileUtils.touch f }

    merge_in, concat_in = [], []
    ffstub = -> arr, fs, out {
      arr << fs
      FileUtils.touch out
    }.curry

    replace_method cat, :ffmerge, ffstub[merge_in] do
      replace_method cat, :ffconcat, ffstub[concat_in] do
        cat.cat infiles
      end
    end

    assert_equal merge.sort, merge_in.sort
    assert_equal concat.sort, concat_in.sort
    assert_equal final.sort, Pathname(".").glob("*").sort
  end

  private def replace_method(obj, m, body)
    cl = obj.singleton_class
    old = cl.instance_method m
    visibility = %i(public protected private).
      find { |v| cl.public_send "#{v}_method_defined?", m } \
        or raise "visibility not found"
    cl.define_method m, &body
    cl.__send__ visibility, m
    begin
      yield
    ensure
      cl.define_method m, old
      cl.__send__ visibility, m
    end
  end
end
