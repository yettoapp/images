# syntax = docker/dockerfile:1.11

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.4.5
# Node version to use in base image
ARG NODE_VERSION=24.4.1

# Debian image to use for base images
ARG DEBIAN_VERSION="bookworm"

# Node image to use for base images
FROM docker.io/node:${NODE_VERSION}-${DEBIAN_VERSION}-slim AS node

# Ruby image to use for base image
FROM docker.io/ruby:${RUBY_VERSION}-slim-${DEBIAN_VERSION} AS ruby

ONBUILD ARG APP_ENV

# Set environment for Ruby on Rails
ONBUILD ENV RAILS_ENV=${APP_ENV:-development}
# Set environment for Node
ONBUILD ENV NODE_ENV=${APP_ENV:-development}

# if true, builds the assets and uploads them to S3
ONBUILD ARG WITH_ASSETS
ONBUILD ENV WITH_ASSETS=${WITH_ASSETS:-}

ONBUILD ARG S3_BUCKET_NAME
ONBUILD ENV S3_BUCKET_NAME=${S3_BUCKET_NAME:-}

# Set default shell used for running commands
SHELL ["/bin/bash", "-o", "pipefail", "-o", "errexit", "-c"]

RUN \
    # Remove automatic apt cache Docker cleanup scripts
    rm -f /etc/apt/apt.conf.d/docker-clean;

# Rails app lives here
WORKDIR /app

ENV DEBIAN_FRONTEND="noninteractive"

# Common dependencies
RUN \
    # Using --mount to speed up build with caching, see https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/reference.md#run---mount
    --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked \
    --mount=type=tmpfs,target=/var/log \
    # Remove automatic apt cache Docker cleanup scripts
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache; \
    # Apt update & upgrade to check for security updates to Debian image
    apt-get update -qq && \
    apt-get -yq dist-upgrade && \
    apt-get install -yq --no-install-recommends  \
    build-essential \
    libpq-dev \
    cmake \
    gnupg2 \
    curl \
    unzip \
    less \
    git \
    ;

# version of AWS CLI to use for asset uploads
ARG AWSCLI_VERSION=linux-x86_64-2.26.5

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-${AWSCLI_VERSION}.zip" -o "awscli.zip" && \
    unzip awscli.zip && \
    ./aws/install; \
    rm awscli.zip \
    ;

FROM ruby AS builder

ARG WITH_ASSETS
ARG AWSCLI_VERSION
ARG RAILS_ENV
ARG NODE_ENV

COPY --from=node /usr/local/bin /usr/local/bin
COPY --from=node /usr/local/lib /usr/local/lib

ONBUILD COPY package*.json /app/

# Copy the files needed for installing gems
ONBUILD COPY Gemfile Gemfile.lock /app/

# Pass ruby version
ONBUILD RUN echo $RUBY_VERSION > /app/.ruby-version

ONBUILD RUN \
    # Mount Ruby Gem caches
    --mount=type=cache,id=gem-cache-${RAILS_ENV},target=/usr/local/bundle/cache/,sharing=locked \
    # Configure bundle to prevent changes to Gemfile and Gemfile.lock
    bundle config set --global frozen "true"; \
    # Configure bundle to not cache downloaded Gems
    bundle config set --global cache_all "false"; \
    # Configure bundle to only process production Gems
    bundle config set --local without "development test"; \
    # Configure bundle to not warn about root user
    bundle config set silence_root_warning "true"; \
    # Download and install required Gems
    bundle install -j"$(nproc)"; \
    # Precompile gems with Bootsnap (and ignore errors)
    bundle exec bootsnap precompile --gemfile || true && \
    # Remove unneeded gems
    bundle clean --force;

# Copy the whole application folder into the image
ONBUILD COPY . /app

# Precompile application code with Bootsnap (and ignore errors)
ONBUILD RUN bundle exec bootsnap precompile app/ lib/ || true

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
ONBUILD RUN bash -c 'if [[ "$WITH_ASSETS" != "" ]]; then \
    set -ex; \
    if [[ -f "/app/package.json" ]]; then \
    # for vite, etc \
    NODE_ENV=development npm install; \
    NODE_ENV=production npm run build_translations --if-present; \
    fi; \
    RAILS_ENV=production PRECOMPILING=1 SECRET_KEY_BASE=DUMMY /app/bin/rails assets:precompile; \
    rm -fr /app/tmp;  \
    fi'

# Upload assets to S3
ONBUILD RUN \
    --mount=type=secret,id=AWS_ACCESS_KEY_ID,env=AWS_ACCESS_KEY_ID \
    --mount=type=secret,id=AWS_SECRET_ACCESS_KEY,env=AWS_SECRET_ACCESS_KEY \
    bash -c 'if [[ "$RAILS_ENV" = "production" && "$S3_BUCKET_NAME" != "" ]]; then \
    aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID; \
    aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY; \
    aws s3 sync /app/public/ s3://$S3_BUCKET_NAME; \
    aws configure set aws_access_key_id "reset"; \
    aws configure set aws_secret_access_key "reset"; \
    fi'

ONBUILD RUN rm -rf node_modules vendor/bundle test
