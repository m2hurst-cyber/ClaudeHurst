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
        resources :skills, only: %i[index show], constraints: { id: /[a-z0-9-]+/ } do
          member { put :vote }
        end
        resources :areas, only: :index
        resources :candidates, only: %i[index show] do
          member do
            post :approve
            post :reject
          end
        end
        resources :procedures, only: :create
        resources :prompts, only: :index do
          member { post :respond }
        end
        resources :commands, only: :index
        resources :bundles, only: :show, constraints: { id: /[a-z0-9-]+/ }
        resources :resources, only: [] do
          member { get :download }
        end
      end

      resources :events, only: :create
      resources :skills, only: %i[index show], constraints: { id: /[a-z0-9-]+/ } do
        resources :rest_stops, only: :index
      end
      resources :rest_stops, only: :show
      get :route, to: "routes#show"
      get :market, to: "skills#market"
      get :fields, to: "skills#fields"
      get :commands, to: "commands#index"
      get "bundles/:id", to: "commands#bundle", as: :bundle, constraints: { id: /[a-z0-9-]+/ }
      get :resources, to: "commands#resources"
      get "resources/*path", to: "commands#resource", as: :resource, format: false
      get :search, to: "places#search"
      get "places/:key", to: "places#show", as: :place, constraints: { key: /[^\/]+?/ }, format: /json|md/
    end
  end

  authenticate :user do
    root "skills#index"
    get "map", to: "skill_maps#show", as: :skill_map
    get "map/route", to: "skill_maps#route", as: :skill_map_route
    get "map/areas", to: "skill_maps#areas", as: :skill_map_areas
    get "map/fields", to: "skill_maps#fields", as: :skill_map_fields
    get "map/search", to: "places#search", as: :map_search
    scope "map/places", constraints: { key: /[^\/]+?/ }, format: /html|json|md/ do
      get ":key", to: "places#show", as: :place
      get ":key/edit", to: "places#edit", as: :edit_place
      patch ":key", to: "places#update"
    end

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
      resource :vote, only: :update, controller: :skill_votes
      resources :resources, only: %i[create destroy], controller: :skill_resources
      resource :classification, only: :update, controller: :skill_classifications do
        post :confirm
        post :reinfer
      end
      resources :promotions, only: :create
      resources :rest_stops, only: :create
      member do
        get :compare
        get :download
        post :deprecate
      end
    end
    resources :rest_stops, only: %i[show update] do
      member { post :revert }
    end
    resources :prompts, only: :index do
      member { post :respond }
    end
    resources :connected_apps, only: %i[index destroy]
    resources :resources, only: %i[index show create update destroy] do
      member { get :download }
    end
    resources :resource_folders, only: :create
    post "map/send", to: "skill_commands#create", as: :map_send
    get "map/sent", to: "skill_commands#index", as: :map_sent
    resources :promotions, only: :index do
      member do
        post :approve
        post :reject
        post :withdraw
      end
    end
    resources :bounties, only: :index do
      member do
        post :approve
        post :reject
        post :close
      end
    end
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
      resource :pricing, only: %i[show update], controller: :pricing
      resource :gates, only: %i[show update]
      resource :protocols, only: %i[show update]
      resources :fields, only: %i[index create update destroy]
    end
  end
end
