# discourse-meta-tag

A server-side Discourse plugin for hobbyDB's generic link previews. It returns the five requested Open Graph tags in the HTML `<head>` when an **anonymous link-preview bot** requests an existing, non-deleted topic it cannot access.

The fallback contains only the forum URL, name, description and image. It never includes a topic's title, slug, posts or category. Missing and deleted topics retain Discourse's normal response.

## Scope

- Matches Discord, Slack, Twitter/X, Facebook, LinkedIn, Telegram, WhatsApp, Skype and Microsoft preview user agents.
- Applies only to HTML GET requests handled by `TopicsController#show`.
- Handles topic access errors (403/404) only after confirming that the topic exists, is not deleted, and is inaccessible according to Guardian or the site-wide login requirement.
- Leaves missing/deleted topics on Discourse's normal error path. On a login-required forum, their normal login redirect is preserved because Discourse redirects before opening a topic.
- Returns HTTP 200 for the generic preview, since preview services can discard error responses.
- Preserves valid permalink redirects.
- Leaves public topic rendering, all logged-in requests, ordinary browsers, JSON/XHR requests and non-topic routes on Discourse's normal paths.
- Prevents storage of the fallback in Discourse's anonymous cache and sets `Cache-Control: private, no-store` and `X-Robots-Tag: noindex, nofollow`.

User-agent matching selects a generic response; it grants no access to topic data. Bots blocked by Discourse's crawler blocklist, a reverse proxy or a firewall never reach this plugin.

## Compatibility with discourse-redirect-404

Restricted-topic previews are handled before the application-level 404 redirect handler. With both plugins enabled, an anonymous preview bot receives the generic metadata for an existing restricted topic; missing/deleted topics and ordinary browser or logged-in requests retain the redirect plugin's behavior. Visible permalink targets retain the existing redirect handling.

No changes to `discourse-redirect-404` are needed. The standalone suite loads an exact copy of the supplied redirect plugin as a fixture to verify the interaction. The compatibility request specs run when that plugin is also installed in the Discourse test checkout; otherwise that group is skipped.

## Installation

Install this folder as `plugins/discourse-meta-tag` in the Discourse server checkout/container and restart Discourse. The source is on the `preview-meta-tags` branch of `https://github.com/umer-nazir02/discourse-plugins`.

For a standard Docker deployment, add this command to the existing plugin installation hook in `/var/discourse/containers/app.yml` that runs inside `/var/www/discourse/plugins`:

```sh
git clone --branch preview-meta-tags https://github.com/umer-nazir02/discourse-plugins.git discourse-meta-tag
```

Then rebuild the app container with `./launcher rebuild app` from `/var/discourse`.

The plugin's `discourse_meta_tag_enabled` site setting is enabled by default. Disable it to restore the original behavior. The supplied hobbyDB metadata is defined in `lib/discourse_meta_tag/topic_preview.rb`.

A theme component cannot provide this behavior: preview bots need server-rendered HTML before JavaScript runs.

## Verification

Standalone boundary tests (Ruby and Minitest, no Discourse required):

```sh
ruby test/topic_preview_test.rb
```

Request specs, from the root of a Discourse development/test checkout with this plugin installed:

```sh
LOAD_PLUGINS=1 bundle exec rspec plugins/discourse-meta-tag/spec/requests/topic_preview_spec.rb
```

The request specs exercise real routes, authentication, Guardian permissions, restricted categories, private messages, missing/deleted topics, login requirements, public-topic regressions and compatibility with `discourse-redirect-404` when installed. Standalone tests cannot verify those Discourse integrations.

After installation, test an inaccessible topic with a preview user agent:

```sh
curl -i -A 'Discordbot/2.0' 'https://forum.hobbydb.com/t/example/123'
```

Expect HTTP 200 and the five generic `og:*` tags in `<head>`. Use an existing, non-deleted restricted topic URL. A missing or deleted topic should retain the usual error or login redirect. A public topic should retain its topic-specific tags; a normal browser should retain the usual error or login response. Preview services may cache earlier previews, so an existing Discord or Slack preview may not refresh immediately.

## Local validation limits

The standalone tests and Ruby syntax checks can run in this workspace. Full Discourse request specs require a Discourse checkout and its services; they have not been executed here.
