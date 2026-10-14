# frozen_string_literal: true

require "rails_helper"

RSpec.describe "hobbyDB inaccessible topic previews", type: :request do
  fab!(:restricted_group, :group)
  fab!(:restricted_category) { Fabricate(:private_category, group: restricted_group) }
  fab!(:restricted_topic) do
    Fabricate(:topic, category: restricted_category, title: "Secret collectible discussion")
  end
  fab!(:restricted_post) do
    Fabricate(:post, topic: restricted_topic, raw: "Private collectible details must never leak")
  end
  fab!(:public_post, :post)
  fab!(:user, :user)

  let(:bot_headers) { { "HTTP_USER_AGENT" => "Discordbot/2.0", "HTTP_ACCEPT" => "text/html" } }

  before do
    SiteSetting.discourse_meta_tag_enabled = true
    SiteSetting.login_required = false
  end

  def head_metadata
    Nokogiri::HTML5(response.body).css("head meta[property^='og:']").map do |tag|
      [tag["property"], tag["content"]]
    end
  end

  def expect_generic_preview
    expect(response.status).to eq(200)
    expect(response.media_type).to eq("text/html")
    expect(head_metadata).to eq(
      [
        ["og:url", "https://forum.hobbydb.com"],
        ["og:type", "website"],
        ["og:title", "hobbyDB Forum"],
        ["og:description", "Where the hobbyDB community gets together and discusses all aspects of collectibles"],
        ["og:image", "https://opengraph.b-cdn.net/production/images/52b8d79f-9c0d-4441-85b4-9dff663cd614.png?token=TVPBILpB0wduTmeJVNAAosLh9NbbJ-iVL4V8YBSp0wI&height=531&width=1016&expires=33280731415"],
      ],
    )
    expect(response.body).not_to include(restricted_topic.title, restricted_post.raw)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
  end

  def expect_normal_topic_response(url)
    SiteSetting.discourse_meta_tag_enabled = false
    get url, headers: bot_headers
    original_status = response.status
    original_metadata = head_metadata
    original_location = response.headers["Location"]

    SiteSetting.discourse_meta_tag_enabled = true
    get url, headers: bot_headers
    expect(response.status).to eq(original_status)
    expect(head_metadata).to eq(original_metadata)
    expect(response.headers["Location"]).to eq(original_location)
    expect(response.body).not_to include('content="hobbyDB Forum"')
  end

  [true, false].each do |detailed|
    it "previews a restricted category topic with detailed_404=#{detailed}" do
      SiteSetting.detailed_404 = detailed
      get restricted_topic.relative_url, headers: bot_headers
      expect_generic_preview
    end
  end

  it "previews a private message without disclosing its contents" do
    private_post = Fabricate(:private_message_post)
    get private_post.topic.relative_url, headers: bot_headers
    expect_generic_preview
    expect(response.body).not_to include(private_post.topic.title, private_post.raw)
  end

  it "preserves the normal 404 for a nonexistent topic" do
    expect_normal_topic_response("/t/nonexistent/999999999")
    expect(response.status).to eq(404)
  end

  [true, false].each do |detailed|
    it "preserves the normal error for a deleted topic with detailed_404=#{detailed}" do
      SiteSetting.detailed_404 = detailed
      public_post.topic.trash!
      expect_normal_topic_response(public_post.topic.relative_url)
      expect([404, 410]).to include(response.status)
    end
  end

  it "preserves the normal error for a deleted restricted topic" do
    restricted_topic.trash!
    expect_normal_topic_response(restricted_topic.relative_url)
    expect([403, 404, 410]).to include(response.status)
  end

  it "preserves a public topic error instead of treating it as restricted" do
    expect_normal_topic_response("#{public_post.topic.relative_url}?page=-1")
    expect(response.status).to eq(404)
  end

  it "preserves login redirects for nonexistent and deleted topics on a login-required site" do
    SiteSetting.login_required = true
    expect_normal_topic_response("/t/nonexistent/999999999")
    expect(response.status).to eq(302)
    public_post.topic.trash!
    expect_normal_topic_response(public_post.topic.relative_url)
    expect(response.status).to eq(302)
  end

  it "previews a topic behind the site-wide login requirement" do
    SiteSetting.login_required = true
    get public_post.topic.relative_url, headers: bot_headers
    expect_generic_preview
    expect(response.headers["Location"]).to be_nil
  end

  it "supports Slack link expansion" do
    get restricted_topic.relative_url,
        headers: bot_headers.merge("HTTP_USER_AGENT" => "Slackbot-LinkExpanding 1.0")
    expect_generic_preview
  end

  it "preserves public topic metadata and content for preview bots" do
    SiteSetting.discourse_meta_tag_enabled = false
    get public_post.topic.relative_url, headers: bot_headers
    original_metadata = head_metadata
    original_status = response.status

    SiteSetting.discourse_meta_tag_enabled = true
    get public_post.topic.relative_url, headers: bot_headers
    expect(response.status).to eq(original_status)
    expect(response.status).to eq(200)
    expect(head_metadata).to eq(original_metadata)
    expect(response.body).to include(public_post.topic.title)
    expect(response.body).not_to include('content="https://forum.hobbydb.com"')
  end

  it "preserves logged-in access to restricted topics even with a bot user agent" do
    restricted_group.add(user)
    sign_in(user)
    SiteSetting.discourse_meta_tag_enabled = false
    get restricted_topic.relative_url, headers: bot_headers
    original_metadata = head_metadata

    SiteSetting.discourse_meta_tag_enabled = true
    get restricted_topic.relative_url, headers: bot_headers
    expect(response.status).to eq(200)
    expect(head_metadata).to eq(original_metadata)
    expect(response.body).to include(restricted_topic.title)
  end

  it "preserves logged-in access errors even with a bot user agent" do
    sign_in(user)
    SiteSetting.discourse_meta_tag_enabled = false
    get restricted_topic.relative_url, headers: bot_headers
    original_status = response.status
    original_metadata = head_metadata

    SiteSetting.discourse_meta_tag_enabled = true
    get restricted_topic.relative_url, headers: bot_headers
    expect(response.status).to eq(original_status)
    expect([403, 404]).to include(response.status)
    expect(head_metadata).to eq(original_metadata)
    expect(response.body).not_to include('content="hobbyDB Forum"')
  end

  it "preserves anonymous browser access errors" do
    get restricted_topic.relative_url,
        headers: bot_headers.merge("HTTP_USER_AGENT" => "Mozilla/5.0")
    expect([403, 404]).to include(response.status)
    expect(response.body).not_to include('content="hobbyDB Forum"')
  end

  it "preserves JSON and XHR requests" do
    get "#{restricted_topic.relative_url}.json",
        headers: bot_headers.merge("HTTP_ACCEPT" => "application/json")
    expect([403, 404]).to include(response.status)
    expect(response.media_type).to eq("application/json")

    get restricted_topic.relative_url,
        headers: bot_headers.merge("HTTP_X_REQUESTED_WITH" => "XMLHttpRequest")
    expect([403, 404]).to include(response.status)
    expect(response.body).not_to include('content="hobbyDB Forum"')
  end

  it "preserves login redirects for ordinary browsers" do
    SiteSetting.login_required = true
    get public_post.topic.relative_url,
        headers: bot_headers.merge("HTTP_USER_AGENT" => "Mozilla/5.0")
    expect(response.status).to eq(302)
  end

  it "preserves redirects to valid public permalink targets" do
    Permalink.create!(url: "/t/old-collectible/999999999", topic_id: public_post.topic.id)
    get "/t/old-collectible/999999999", headers: bot_headers
    expect(response.status).to eq(301)
  end

  it "preserves non-topic errors" do
    get "/categories/not-a-category/999999999", headers: bot_headers
    expect(response.status).to eq(404)
    expect(response.body).not_to include('content="hobbyDB Forum"')
  end
end
