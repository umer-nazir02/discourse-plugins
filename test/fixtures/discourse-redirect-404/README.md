# Redirect plugin compatibility fixture

`plugin.rb` is an unchanged copy of the user-supplied `discourse-redirect-404` version 1.0.0. The standalone test loader executes its `after_initialize` block against a controller boundary so tests exercise its actual `ApplicationController` prepend, redirect condition and early return.

This fixture is test data and is not loaded by the preview plugin in production. The real Discourse compatibility request specs require the redirect plugin to be installed separately.
