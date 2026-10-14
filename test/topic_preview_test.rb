# frozen_string_literal: true

require "minitest/autorun"
require "ostruct"
require "cgi"

require_relative "../lib/discourse_meta_tag/topic_preview"

module SiteSetting
  class << self
    attr_accessor :discourse_meta_tag_enabled, :login_required

    def login_required?
      login_required
    end
  end
end

module Topic
  class << self
    attr_accessor :record

    def find_by(id:, **_conditions)
      record if record && id.to_s == "123"
    end

    def find_by_slug(slug)
      record if slug == "restricted-topic"
    end
  end
end

# A minimal controller boundary for running the plugin without Rails.
# Full routing, authentication and Guardian checks live in the request specs.
class PreviewController
  attr_accessor :current_user, :action_name, :request, :response, :params, :visible

  def initialize
    @action_name = "show"
    @params = { id: "123" }
    @visible = false
    @request = OpenStruct.new(
      get?: true,
      xhr?: false,
      format: OpenStruct.new(html?: true),
      user_agent: "Discordbot/2.0",
      env: { "ANON_CACHE_DURATION" => 60 },
    )
    @response = OpenStruct.new(status: 200, headers: {}, content_type: "text/html")
  end

  def guardian
    self
  end

  def can_see?(_topic)
    visible
  end

  def response_body=(body)
    response.body = body
  end

  def rescue_discourse_actions(type, status_code, opts = nil)
    response.status = opts && opts[:permalink] ? 301 : status_code
    response.body = "Original #{type} response"
    :original_result
  end

  def redirect_to_login_if_required
    response.status = 302
    response.headers["Location"] = "/login"
    response.body = "Original login redirect"
  end
end

PreviewController.prepend(DiscourseMetaTag::TopicPreview)

class TopicPreviewTest < Minitest::Test
  def setup
    SiteSetting.discourse_meta_tag_enabled = true
    SiteSetting.login_required = false
    Topic.record = OpenStruct.new(deleted_at: nil)
    @controller = PreviewController.new
  end

  def test_restricted_topic_returns_only_generic_metadata
    @controller.rescue_discourse_actions(:invalid_access, 403)
    assert_equal 200, @controller.response.status
    body = @controller.response.body
    head = body[/<head>(.*?)<\/head>/m, 1]
    refute_nil head
    tags = head.scan(/<meta property="([^"]+)" content="([^"]*)">/).to_h
    assert_equal "https://forum.hobbydb.com", tags["og:url"]
    assert_equal "website", tags["og:type"]
    assert_equal "hobbyDB Forum", tags["og:title"]
    assert_equal "Where the hobbyDB community gets together and discusses all aspects of collectibles", tags["og:description"]
    assert_equal "https://opengraph.b-cdn.net/production/images/52b8d79f-9c0d-4441-85b4-9dff663cd614.png?token=TVPBILpB0wduTmeJVNAAosLh9NbbJ-iVL4V8YBSp0wI&height=531&width=1016&expires=33280731415", CGI.unescapeHTML(tags.fetch("og:image"))
    assert_equal 5, tags.size
    refute_includes body, "Original"
    assert_equal "private, no-store", @controller.response.headers["Cache-Control"]
    assert_nil @controller.request.env["ANON_CACHE_DURATION"]
  end

  def test_all_supported_access_errors_receive_fallback
    [[:not_found, 404], [:not_logged_in, 403]].each do |type, status|
      @controller.rescue_discourse_actions(type, status)
      assert_equal 200, @controller.response.status
    end
  end

  def test_missing_topic_preserves_original_error
    Topic.record = nil
    assert_original_error
  end

  def test_deleted_topic_preserves_original_404_and_410
    Topic.record.deleted_at = Time.now
    assert_original_error
    @controller.rescue_discourse_actions(:not_found, 410)
    assert_equal 410, @controller.response.status
    assert_equal "Original not_found response", @controller.response.body
  end

  def test_existing_public_topic_with_error_is_unaffected
    @controller.visible = true
    assert_original_error
  end

  def test_missing_and_deleted_topics_preserve_login_redirect
    SiteSetting.login_required = true
    Topic.record = nil
    @controller.send(:redirect_to_login_if_required)
    assert_equal 302, @controller.response.status
    assert_equal "Original login redirect", @controller.response.body
    Topic.record = OpenStruct.new(deleted_at: Time.now)
    @controller.send(:redirect_to_login_if_required)
    assert_equal 302, @controller.response.status
  end

  def test_topic_id_alias_and_slug_only_urls_are_supported
    @controller.params = { topic_id: "123" }
    @controller.rescue_discourse_actions(:not_found, 404)
    assert_equal 200, @controller.response.status
    @controller.params = { id: "restricted-topic" }
    @controller.rescue_discourse_actions(:not_found, 404)
    assert_equal 200, @controller.response.status
  end

  def test_invalid_topic_identifiers_preserve_original_error
    [nil, ["123"], { id: "123" }, "999999999999999999999999999999"].each do |id|
      @controller.params = { id: id }
      assert_original_error
    end
  end

  def test_slack_and_other_preview_bots_receive_fallback
    ["Slackbot-LinkExpanding 1.0", "Slack-ImgProxy", "Twitterbot/1.0", "facebookexternalhit/1.1", "LinkedInBot", "TelegramBot", "WhatsApp/2.0", "SkypeUriPreview", "MicrosoftPreview/2.0"].each do |agent|
      @controller.request.user_agent = agent
      @controller.rescue_discourse_actions(:not_found, 404)
      assert_equal 200, @controller.response.status, agent
    end
  end

  def test_logged_in_requests_preserve_errors_even_with_bot_user_agent
    @controller.current_user = Object.new
    assert_original_error
  end

  def test_normal_browsers_search_crawlers_and_missing_user_agents_are_unaffected
    ["Mozilla/5.0", "Googlebot", nil, ""].each do |agent|
      @controller.request.user_agent = agent
      assert_original_error
    end
  end

  def test_json_xhr_non_get_and_other_actions_are_unaffected
    @controller.request.format = OpenStruct.new(html?: false)
    assert_original_error
    setup
    @controller.request[:xhr?] = true
    assert_original_error
    setup
    @controller.request[:get?] = false
    assert_original_error
    setup
    @controller.action_name = "posts"
    assert_original_error
  end

  def test_disabled_plugin_is_unaffected
    SiteSetting.discourse_meta_tag_enabled = false
    assert_original_error
  end

  def test_invalid_parameters_and_server_errors_are_unaffected
    [[:invalid_parameters, 400], [:not_found, 400], [:read_only, 503]].each do |type, status|
      @controller.rescue_discourse_actions(type, status)
      assert_equal status, @controller.response.status
      assert_equal "Original #{type} response", @controller.response.body
    end
  end

  def test_permalinks_are_preserved
    @controller.rescue_discourse_actions(:not_found, 404, { permalink: true })
    assert_equal 301, @controller.response.status
    assert_equal "Original not_found response", @controller.response.body
  end

  def test_login_required_topic_request_receives_fallback
    SiteSetting.login_required = true
    @controller.send(:redirect_to_login_if_required)
    assert_equal 200, @controller.response.status
    assert_includes @controller.response.body, 'property="og:title" content="hobbyDB Forum"'
    refute @controller.response.headers.key?("Location")
  end

  def test_normal_login_redirects_are_preserved
    SiteSetting.login_required = true
    @controller.current_user = Object.new
    @controller.send(:redirect_to_login_if_required)
    assert_equal "Original login redirect", @controller.response.body
    setup
    @controller.request.user_agent = "Mozilla/5.0"
    @controller.send(:redirect_to_login_if_required)
    assert_equal "Original login redirect", @controller.response.body
  end

  def test_login_hook_delegates_when_site_does_not_require_login
    @controller.send(:redirect_to_login_if_required)
    assert_equal "Original login redirect", @controller.response.body
    assert_equal 60, @controller.request.env["ANON_CACHE_DURATION"]
  end

  private

  def assert_original_error
    result = @controller.rescue_discourse_actions(:not_found, 404)
    assert_equal :original_result, result
    assert_equal 404, @controller.response.status
    assert_equal "Original not_found response", @controller.response.body
  end
end
