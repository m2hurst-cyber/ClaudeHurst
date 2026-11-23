Rails.application.routes.draw do
  devise_for :users

  get "up" => "rails/health#show", as: :rails_health_check

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
  mount MissionControl::Jobs::Engine, at: "/jobs"

  authenticate :user do
    root to: "dashboards#show"

    resources :companies do
      resources :contacts, shallow: true
      resources :deals, shallow: true, only: %i[index new create]
      resources :products, shallow: true, only: %i[index new create]
      resources :activities, shallow: true, only: %i[index new create]
    end

    resources :contacts, only: %i[show edit update destroy]

    resources :deals, only: %i[index show edit update destroy] do
      resources :activities, shallow: true, only: %i[index new create]
      collection do
        get :pipeline
      end
      member do
        post :advance
      end
    end

    resources :activities, only: %i[show edit update destroy]
    resources :tasks
    resources :reminders do
      member { post :fire }
    end
    resources :notifications, only: %i[index update destroy] do
      collection { post :mark_all_read }
    end

    # Sales
    resources :quotes do
      member do
        post :send_out
        post :mark_accepted
        post :mark_rejected
        get :pdf
      end
    end
    resources :contracts do
      member do
        post :mark_signed
        post :activate
        get :pdf
      end
      resources :pricing_tiers, shallow: true, controller: "contract_pricing_tiers"
    end
    resources :invoices do
      member do
        post :send_out
        post :void_it
        get :pdf
      end
      resources :payments, shallow: true
    end

    # ERP
    resources :products, only: %i[index show edit update destroy] do
      resources :boms, shallow: true
    end
    resources :raw_materials do
      resources :raw_material_lots, shallow: true, path: "lots"
    end
    resources :production_lines
    resources :production_runs do
      member do
        post :release
        post :start_run
        post :complete
        post :close
        post :cancel
        post :create_invoice
      end
    end
    resources :finished_good_lots, only: %i[index show] do
      resources :finished_good_movements, shallow: true, only: %i[new create], path: "movements"
      member { get :trace }
    end

    # Admin
    namespace :admin do
      resources :users
      resources :audit_logs, only: %i[index show]
    end
  end
end
