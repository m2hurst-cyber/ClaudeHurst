Rails.application.routes.draw do
  devise_for :users, skip: :registrations

  get "up" => "rails/health#show", as: :rails_health_check

  # Microsoft Office add-in
  scope :addin, controller: :addin, as: :addin do
    get "manifest.xml", action: :manifest, as: :manifest, defaults: { format: :xml }
    get :taskpane
    get :support
  end
  get "addin/connect", to: "addin_connect#show", as: :addin_connect
  post "addin/connect", to: "addin_connect#create"

  namespace :api do
    namespace :v1 do
      namespace :addin do
        resource :me, only: %i[show destroy], controller: :sessions
        resources :events, only: :create
        resources :skills, only: %i[index show], constraints: { id: /[a-z0-9-]+/ }
        resources :areas, only: :index
        resources :candidates, only: %i[index show] do
          member do
            post :approve
            post :reject
          end
        end
        resources :procedures, only: :create
      end

      resources :events, only: :create
      resources :skills, only: %i[index show], constraints: { id: /[a-z0-9-]+/ }
      get :route, to: "routes#show"
    end
  end

  authenticate :user do
    root "skills#index"
    get "map", to: "skill_maps#show", as: :skill_map
    get "map/route", to: "skill_maps#route", as: :skill_map_route
    get "map/areas", to: "skill_maps#areas", as: :skill_map_areas

    resources :skill_candidates, except: :destroy do
      member do
        post :generate_draft
        post :approve
        post :reject
        post :dismiss
      end
    end
    resources :skills, only: %i[index show edit update] do
      resources :links, only: %i[create destroy], controller: :skill_links, constraints: { id: /[^\/]+/ }
      member do
        get :download
        post :deprecate
      end
    end
    resources :connected_apps, only: %i[index destroy]
    resources :notifications, only: :index do
      collection { post :read_all }
    end

    namespace :admin do
      resources :users, only: %i[index new create edit update]
      resources :sources, only: %i[index new create] do
        member { post :deactivate }
      end
      resources :action_definitions, only: %i[index edit update]
      resources :audit_logs, only: :index
      get :deploy, to: "deploy#show"
    end
  end
end
