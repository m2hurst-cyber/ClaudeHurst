# Skill Capture, as one image. Build it anywhere; it needs a Postgres URL and nothing else.
FROM ruby:3.3.6-slim AS base
WORKDIR /rails
ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/usr/local/bundle BUNDLE_WITHOUT=development:test

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# ---- build ----
FROM base AS build
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY . .
RUN bundle exec bootsnap precompile app/ lib/ || true

# Build the stylesheet and digest the assets.
#
# Precompiling boots the application, so every initializer runs — including the one that
# refuses to start in production without encryption keys. These values are throwaway and
# never touch data: nothing is encrypted or decrypted at build time, and the real keys
# arrive from the environment at run time. There is no database here either, which is
# fine: nothing in the asset build reads one.
RUN SECRET_KEY_BASE=precompile-only \
    SKILL_CAPTURE_ENCRYPTION_PRIMARY_KEY=precompile-only \
    SKILL_CAPTURE_ENCRYPTION_DETERMINISTIC_KEY=precompile-only \
    SKILL_CAPTURE_ENCRYPTION_KEY_DERIVATION_SALT=precompile-only \
    ./bin/rails tailwindcss:build assets:precompile

# ---- run ----
FROM base
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Not as root.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p db log storage tmp && chown -R rails:rails db log storage tmp
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server"]
