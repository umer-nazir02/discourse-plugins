# frozen_string_literal: true

module DiscourseMetaTag
  module TopicPreview
    # Match preview services specifically; Discourse's general crawler detection
    # also treats some ordinary browser user agents as crawlers.
    PREVIEW_BOTS = /Discordbot|Slackbot|Slack-ImgProxy|Twitterbot|facebookexternalhit|Facebot|LinkedInBot|TelegramBot|WhatsApp|SkypeUriPreview|MicrosoftPreview/i
    ACCESS_ERRORS = %i[not_found invalid_access not_logged_in].freeze
    ACCESS_STATUSES = [403, 404].freeze

    HTML = <<~HTML.freeze
      <!DOCTYPE html>
      <html lang="en">
      <head>
      <meta charset="utf-8">
      <title>hobbyDB Forum</title>
      <meta property="og:url" content="https://forum.hobbydb.com">
      <meta property="og:type" content="website">
      <meta property="og:title" content="hobbyDB Forum">
      <meta property="og:description" content="Where the hobbyDB community gets together and discusses all aspects of collectibles">
      <meta property="og:image" content="https://opengraph.b-cdn.net/production/images/52b8d79f-9c0d-4441-85b4-9dff663cd614.png?token=TVPBILpB0wduTmeJVNAAosLh9NbbJ-iVL4V8YBSp0wI&amp;height=531&amp;width=1016&amp;expires=33280731415">
      </head>
      <body><a href="https://forum.hobbydb.com">hobbyDB Forum</a></body>
      </html>
    HTML

    def rescue_discourse_actions(type, status_code, opts = nil)
      use_preview =
        ACCESS_ERRORS.include?(type) && ACCESS_STATUSES.include?(status_code) &&
          hobbydb_preview_request?

      # Let Discourse resolve permalinks and apply its normal error handling first.
      result = super
      return result unless use_preview && ACCESS_STATUSES.include?(response.status) &&
        hobbydb_restricted_topic?

      hobbydb_topic_preview
    end

    private

    def redirect_to_login_if_required
      if SiteSetting.login_required? && hobbydb_preview_request? && hobbydb_restricted_topic?
        hobbydb_topic_preview
      else
        super
      end
    end

    def hobbydb_preview_request?
      SiteSetting.discourse_meta_tag_enabled && action_name == "show" && request.get? &&
        request.format&.html? && !request.xhr? &&
        PREVIEW_BOTS.match?(request.user_agent.to_s) && current_user.nil?
    end

    def hobbydb_restricted_topic?
      # Permissions can be deliberately hidden behind a 404. Resolve the topic
      # independently so a missing/deleted topic never receives the fallback.
      identifier = params[:id] || params[:topic_id]
      return false unless identifier.is_a?(String) || identifier.is_a?(Integer)

      identifier = identifier.to_s
      topic =
        if identifier.match?(/\A\d+\z/)
          return false if identifier.length > 19 || identifier.to_i > 9_223_372_036_854_775_807
          Topic.find_by(id: identifier)
        else
          Topic.find_by_slug(identifier)
        end

      topic && topic.deleted_at.nil? && (SiteSetting.login_required? || !guardian.can_see?(topic))
    end

    def hobbydb_topic_preview
      # AnonymousCache uses this env value independently of Cache-Control.
      request.env.delete("ANON_CACHE_DURATION")
      response.headers["Cache-Control"] = "private, no-store"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      response.content_type = "text/html; charset=utf-8"
      response.status = 200
      # Assigning the completed response avoids a second Rails render after the
      # original error renderer has run, and halts the login before_action.
      self.response_body = HTML
    end
  end
end
