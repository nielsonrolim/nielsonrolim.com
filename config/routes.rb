Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"

  root to: redirect("/pt-BR")

  scope "(:locale)", locale: /pt-BR|en-US/ do
    get "/", to: "pages#home", as: :home
  end

  resources :subscribers, only: [ :create ]

  # One-click unsubscribe referenced by the List-Unsubscribe headers on every
  # newsletter email. GET renders a confirmation, POST performs it (mail clients
  # cannot send DELETE).
  get "newsletter/unsubscribe", to: "unsubscribes#show", as: :unsubscribe
  post "newsletter/unsubscribe", to: "unsubscribes#destroy"

  # Private admin area (HTTP Basic Auth). The RSS reader and the job dashboard
  # both live underneath it.
  namespace :admin do
    root to: "dashboard#index"

    # Job dashboard. Mission Control's controllers inherit Admin::BaseController
    # (see config/application.rb), so this is behind the same credentials.
    mount MissionControl::Jobs::Engine, at: "/jobs"

    # Newsletter list. Removal is a hard delete (see the controller).
    resources :subscribers, only: [ :index, :create, :update, :destroy ] do
      collection do
        delete :bulk_destroy
        get :export
      end
      member { post :resend }
    end
  end

  # The reader keeps its own Reader:: module, its own views and its reader_*
  # route helpers — only the path is nested under /admin, so the URLs become
  # /admin/reader/... without a mass rename of controllers and helpers.
  scope path: "admin" do
    namespace :reader do
      root to: "entries#index"

      resources :feeds, only: [ :index, :create, :edit, :update, :destroy ] do
        member { post :refresh }
        collection { post :refresh_all }
      end

      resources :entries, only: [ :index ] do
        member { post :clip }
      end

      resources :clippings, only: [ :index, :destroy ] do
        member { post :retry_summary }
      end

      resources :newsletters, only: [ :index, :show, :create ]
    end
  end
end
