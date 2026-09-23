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

    # Public signup page, the destination of the "indique essa newsletter" link
    # every email footer carries. Locale-scoped like the home page, so the
    # visitor reads it — and is recorded — in the language they arrived in.
    get "/newsletter", to: "pages#newsletter", as: :newsletter
  end

  resources :subscribers, only: [ :create ]

  # One-click unsubscribe referenced by the List-Unsubscribe headers on every
  # newsletter email. GET renders a confirmation, POST performs it (mail clients
  # cannot send DELETE).
  get "newsletter/unsubscribe", to: "unsubscribes#show", as: :unsubscribe
  post "newsletter/unsubscribe", to: "unsubscribes#destroy"

  # Manage the subscription, from the link every email carries. Deliberately a
  # separate route from the one above: the List-Unsubscribe contract points at
  # the unsubscribe endpoint, and this one is a page a person opens.
  get "newsletter/preferences", to: "preferences#show", as: :preferences
  patch "newsletter/preferences", to: "preferences#update"

  # Session login for the private admin area. Short, explicit URLs; the reader
  # and the job dashboard live under /admin and require a session.
  get    "login",  to: "sessions#new",     as: :new_session
  post   "login",  to: "sessions#create",  as: :session
  delete "logout", to: "sessions#destroy", as: :logout

  # Password reset by email. Only the four actions the controller implements.
  resources :passwords, param: :token, only: [ :new, :create, :edit, :update ]

  # Private admin area (session auth). The RSS reader and the job dashboard
  # both live underneath it.
  namespace :admin do
    root to: "dashboard#index"

    # Job dashboard. Mission Control's controllers inherit Admin::BaseController
    # (see config/application.rb), so this is behind the same login.
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
        member do
          post :clip
          delete :unclip
        end
      end

      resources :clippings, only: [ :index, :create, :edit, :update, :destroy ] do
        member { post :generate_summary }
      end

      resources :newsletters, only: [ :index, :show, :create ]
    end
  end
end
