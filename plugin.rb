# frozen_string_literal: true

# name: discourse-meta-tag
# about: Generic hobbyDB previews for existing restricted topics requested by anonymous link-preview bots.
# version: 0.1.0
# authors: hobbyDB
# url: https://github.com/umer-nazir02/discourse-plugins

enabled_site_setting :discourse_meta_tag_enabled

require_relative "lib/discourse_meta_tag/topic_preview"

after_initialize do
  reloadable_patch do
    TopicsController.prepend(DiscourseMetaTag::TopicPreview)
  end
end
