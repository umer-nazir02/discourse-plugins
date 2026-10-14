# frozen_string_literal: true

# name: discourse-redirect-404
# about: Redirects server-side 404 pages to an external URL (e.g. hobbydb.com/404)
# version: 1.0.0
# authors: Umer Nazir
# url: https://github.com/your-org/discourse-redirect-404

enabled_site_setting :redirect_404_enabled

after_initialize do
  module ::DiscourseRedirect404
    PLUGIN_NAME = "discourse-redirect-404"

    module ApplicationControllerPatch
      # This fires for every Discourse::NotFound raised anywhere in the app:
      #   - missing topics, categories, users, tags
      #   - unknown URL paths that hit Rails (before Ember boots)
      #   - any controller that calls `raise Discourse::NotFound`
      def rescue_discourse_actions(type, status_code, opts = {})
        # Only redirect on genuine 404s, only for HTML (browser) requests,
        # and only when the plugin is enabled with a valid URL configured.
        if status_code == 404 &&
           request.format.html? &&
           !request.xhr? &&
           SiteSetting.redirect_404_enabled &&
           SiteSetting.redirect_404_url.present?

          redirect_to SiteSetting.redirect_404_url, allow_other_host: true
          return
        end

        # For everything else (JSON/API requests, non-404 errors, plugin
        # disabled) fall through to default Discourse error handling.
        super(type, status_code, opts)
      end
    end
  end

  # Prepend so our override sits in front of the original method in the
  # method-resolution chain; `super` still reaches the original.
  ::ApplicationController.prepend(DiscourseRedirect404::ApplicationControllerPatch)
end
