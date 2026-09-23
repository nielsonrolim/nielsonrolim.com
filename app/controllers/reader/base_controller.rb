module Reader
  # The reader lives underneath the authenticated /admin area, so it inherits the
  # admin's session login and layout.
  #
  # This class exists on purpose: keeping the module (rather than flattening into
  # Admin::) is what preserves app/views/reader/** and the reader_* route helpers,
  # and it gives the reader a place for its own before_actions later.
  class BaseController < Admin::BaseController
  end
end
