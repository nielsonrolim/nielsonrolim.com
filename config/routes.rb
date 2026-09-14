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

  # Private RSS reader + newsletter clipping area (HTTP Basic Auth).
  namespace :reader do
    root to: "entries#index"

    resources :feeds, only: [ :index, :create, :destroy ] do
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
