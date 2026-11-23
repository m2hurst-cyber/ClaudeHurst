Rails.application.routes.draw do
  devise_for :users, skip: :registrations

  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :events, only: :create
      resources :skills, only: %i[index show], constraints: { id: /[a-z0-9-]+/ }
    end
  end

  authenticate :user do
    root "skills#index"

    resources :skill_candidates, except: :destroy do
      member do
        post :generate_draft
        post :approve
        post :reject
        post :dismiss
      end
    end
    resources :skills, only: %i[index show edit update] do
      member do
        get :download
        post :deprecate
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
    end
  end
end
