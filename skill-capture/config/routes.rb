Rails.application.routes.draw do
  # The style guide: the design language on its own, no sign-in needed to review it.
  get "design", to: "design#show"

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

  # MCP: one endpoint any agent can speak to (POST), plus a plain description (GET).
  post "mcp", to: "mcp#handle"
  get "mcp", to: "mcp#discover"

  namespace :api do
    namespace :v1 do
      namespace :addin do
        resource :me, only: %i[show destroy], controller: :sessions
        resources :events, only: :create
        resources :skills, only: %i[index show], constraints: { id: /[a-z0-9-]+/ } do
          member { put :vote }
          resources :runs, only: :create, controller: :skill_runs
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
        resources :worksheet_captures, only: %i[create show]
        resources :flows, only: %i[index show create update]
        resources :flow_runs, only: %i[create show] do
          member do
            post :complete
            post :complete_part
            post :resume
            post :hold
            post :release
            post :jump
            post :skip
            post :insert
          end
        end
        get :agents, to: "flows#agents"
        resources :transfers, only: %i[index create] do
          member do
            post :accept
            post :decline
          end
          collection { get :coworkers }
        end
        resources :bundles, only: :show, constraints: { id: /[a-z0-9-]+/ }
        resources :resources, only: [] do
          member { get :download }
        end
      end

      resources :events, only: :create
      resources :skills, only: %i[index show], constraints: { id: /[a-z0-9-]+/ } do
        resources :rest_stops, only: :index
        resources :runs, only: :create, controller: :skill_runs
      end
      resources :rest_stops, only: :show
      get :route, to: "routes#show"
      get :market, to: "skills#market"
      get :fields, to: "skills#fields"
      get :commands, to: "commands#index"
      resources :flow_runs, only: :show do
        member do
          post :complete
          post :complete_part
        end
      end
      get "bundles/:id", to: "commands#bundle", as: :bundle, constraints: { id: /[a-z0-9-]+/ }
      get :resources, to: "commands#resources"
      get "resources/*path", to: "commands#resource", as: :resource, format: false
      get :search, to: "places#search"
      get "places/:key", to: "places#show", as: :place, constraints: { key: /[^\/]+?/ }, format: /json|md/
    end
  end

  authenticate :user do
    root "find#show"
    get "find", to: "find#show"
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
        patch :audience
      end
    end
    resources :rest_stops, only: %i[show update] do
      member { post :revert }
    end
    resources :prompts, only: :index do
      member { post :respond }
    end
    resources :formulas, only: %i[index create update] do
      collection do
        post :import
        get :guide
      end
    end
    resources :flows do
      member { post :run }
    end
    resources :macro_reviews, path: "macros", only: %i[index show update] do
      member do
        post :screen
        post :copy
        patch :share
        get :export
      end
      collection do
        post :screen_all
        post :import
        get :library
      end
    end
    resources :model_profiles, path: "models", only: %i[index update]
    resources :flow_runs, path: "flow-runs", only: :show do
      member do
        post :complete
        post :complete_part
        post :cancel
        post :resume
        post :hold
        post :release
        post :jump
        post :skip
        post :insert
      end
    end
    resources :transfers, only: %i[index new create show] do
      member do
        post :accept
        post :decline
        post :cancel
        get :delivered
      end
    end
    resources :worksheet_captures, path: "captures", only: %i[index show] do
      member { get "files/:file", action: :file, as: :file, constraints: { file: /[A-Za-z]+\.(md|json)/ } }
    end
    resources :playbooks, only: %i[index show], constraints: { id: /[a-z0-9-]+/ } do
      member { post :install }
    end
    resources :playbook_runs, path: "returns", only: %i[create show update] do
      member do
        patch :inputs
        post :prepare
        post :attest
        post :acknowledge
        post :request_review
        post :sign_off
        post :situation
        post :send_route
        post :complete
        post :generate
        post :deliver
      end
      resources :documents, controller: :return_documents, only: %i[create show update destroy] do
        member { post :read }
      end
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
      resource :protocols, only: %i[show update] do
        get :preview, on: :member
      end
      resources :fields, only: %i[index create update destroy]
    end
  end
end
