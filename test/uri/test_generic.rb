# frozen_string_literal: true

require "test_helper"

class URI::TestGenericTest < Test::Unit::TestCase
  def test_parse
    uri = URI.parse("http://john.doe@foo.com/posts?id=30&limit=5#time=1305298413")
    assert_equal "http", uri.scheme
    assert_equal "foo.com", uri.host
    assert_equal 80, uri.port
    assert_equal "/posts", uri.path
    assert_equal "id=30&limit=5", uri.query
    assert_equal "time=1305298413", uri.fragment
    assert_equal "john.doe", uri.userinfo

    uri = URI.parse("mailto:example@example.com")
    assert_equal "mailto", uri.scheme
    assert_equal "example@example.com", uri.to

    assert_raises(URI::WhatwgParser::ParseError) do
      URI.parse(nil)
    end

    uri = URI.parse("file://localhost/")
    assert_equal "file:///", uri.to_s
  end

  def test_join
    uri = URI.join("http://www.ruby-lang.org/")
    assert_equal uri.to_s, "http://www.ruby-lang.org/"

    uri = URI.join("http://www.ruby-lang.org/", "/ja/man-1.6/")
    assert_equal uri.to_s, "http://www.ruby-lang.org/ja/man-1.6/"

    uri = URI.join("http://www.ruby-lang.org/", "/ja/man-1.6/", "b")
    assert_equal uri.to_s, "http://www.ruby-lang.org/ja/man-1.6/b"
  end

  def test_route_to
    uri = URI.parse('http://my.example.com')
    assert_equal "main.rbx?page=1", uri.route_to("http://my.example.com/main.rbx?page=1").to_s
  end

  def test_merge
    uri = URI.parse("http://foo")
    assert_equal "http://foo/bar", uri.merge("/bar").to_s

    uri = URI.parse("http://foo")
    assert_equal "http://bar/", uri.merge("http://bar").to_s

    uri = URI.parse("http://foo") + "a.html"
    assert_equal "http://foo/a.html", uri.to_s
  end

  def test_split
    result = URI.split("https://john.doe@www.example.com:123/forum/questions/?tag=networking&order=newest#top")
    assert_equal "https", result[0]
    assert_equal "john.doe", result[1]
    assert_equal "www.example.com", result[2]
    assert_equal 123, result[3]
    assert_nil result[4]
    assert_equal "/forum/questions/", result[5]
    assert_nil result[6]
    assert_equal "tag=networking&order=newest", result[7]
    assert_equal "top", result[8]

    result = URI.split("http://john.doe@www.example.com:123/forum/questions/?tag=networking&order=newest#top")
    assert_equal "http", result[0]
  end

  def test_setters
    uri = URI.parse("http://example.com")

    uri.scheme = "https"
    assert_equal "https", uri.scheme
    uri.user = "john.doe"
    assert_equal "john.doe", uri.user
    uri.user = "ユーザ"
    assert_equal "%E3%83%A6%E3%83%BC%E3%82%B6", uri.user
    uri.password = "パスワード"
    assert_equal "%E3%83%91%E3%82%B9%E3%83%AF%E3%83%BC%E3%83%89", uri.password
    uri.host = "www.example.com"
    assert_equal "www.example.com", uri.host
    uri.port = 8443
    assert_equal 8443, uri.port
    uri.path = "/index.html"
    assert_equal "/index.html", uri.path

    assert_raises(URI::InvalidURIError) do
      uri.opaque = "a"
    end
  end

  def test_build
    uri = URI::HTTP.build(host: "www.example.com")
    assert_equal "http://www.example.com", uri.to_s

    uri = URI::HTTP.build(host: "www.example.com", path: "/index.html", query: "id=10")
    assert_equal "http://www.example.com/index.html?id=10", uri.to_s

    # Test all possible arguments
    uri = URI::HTTP.build(
      scheme: "http",
      host: "www.example.com",
      port: 8080,
      path: "/foo/bar",
      query: "x=1&y=2",
      fragment: "frag",
      userinfo: "user:pass"
    )
    assert_equal "http://user:pass@www.example.com:8080/foo/bar?x=1&y=2#frag", uri.to_s
  end
end
