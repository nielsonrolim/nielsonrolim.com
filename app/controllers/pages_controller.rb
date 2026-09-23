class PagesController < ApplicationController
  def home
  end

  # Standalone newsletter signup page, reached from the "indique essa
  # newsletter" link in the email footer. The form posts to the same endpoint
  # the home page uses (see SubscribersController#create).
  def newsletter
  end
end
