# syntax = docker/dockerfile:1.11

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.3.4
# Node version to use in base image
ARG NODE_VERSION=22.11.0

# version of AWS CLI to use for asset uploads
ARG AWSCLI_VERSION=linux-x86_64-2.14.3

# Debian image to use for base images
ARG DEBIAN_VERSION="bookworm"

# Node image to use for base images
FROM docker.io/node:${NODE_VERSION}-${DEBIAN_VERSION}-slim AS node

# Ruby image to use for base image
FROM docker.io/ruby:${RUBY_VERSION}-slim-${DEBIAN_VERSION} AS ruby

ARG APP_ENV
# Set environment for Ruby on Rails
ENV RAILS_ENV=${APP_ENV:-production}
# Set environment for Node
ENV NODE_ENV=${APP_ENV:-production}

# if true, builds the assets and uploads them to S3
ONBUILD ARG WITH_ASSETS
ONBUILD ENV WITH_ASSETS=${WITH_ASSETS:-}

ARG S3_BUCKET_NAME
ENV S3_BUCKET_NAME=${S3_BUCKET_NAME:-}

# Set default shell used for running commands
SHELL ["/bin/bash", "-o", "pipefail", "-o", "errexit", "-c"]

RUN \
    # Remove automatic apt cache Docker cleanup scripts
    rm -f /etc/apt/apt.conf.d/docker-clean;

# Rails app lives here
WORKDIR /app

# Common dependencies
RUN \
    # Using --mount to speed up build with caching, see https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/reference.md#run---mount
    --mount=type=cache,id=apt-cache-${RAILS_ENV},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib-${RAILS_ENV},target=/var/lib/apt,sharing=locked \
    --mount=type=tmpfs,target=/var/log \
    # Remove automatic apt cache Docker cleanup scripts
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache; \
    # Apt update & upgrade to check for security updates to Debian image
    apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get -yq dist-upgrade && \
    DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends  \
    build-essential \
    libpq-dev \
    cmake \
    gnupg2 \
    curl \
    unzip \
    less \
    git \
    ;

# Install AWS CLI
ONBUILD RUN if [[ "$RAILS_ENV" = "production" && "$WITH_ASSETS" != "" ]]; then \
    curl "https://awscli.amazonaws.com/awscli-exe-${AWSCLI_VERSION}.zip" -o "awscli.zip" && \
    unzip awscli.zip && \
    ./aws/install; \
    fi

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
ONBUILD RUN if [[ "$RAILS_ENV" = "production" && "$WITH_ASSETS" != "" ]]; then \
    set -ex \
    # for postcss, etc
    NODE_ENV=development npm install \
    RAILS_ENV=production PRECOMPILING=1 SECRET_KEY_BASE=DUMMY bin/rails assets:precompile \
    rm -fr /app/tmp; \
    fi

# Upload assets to S3
ONBUILD RUN if [[ "$RAILS_ENV" = "production" && "$WITH_ASSETS" != "" ]]; then \
    --mount=type=secret,id=AWS_ACCESS_KEY_ID \
    --mount=type=secret,id=AWS_SECRET_ACCESS_KEY \
    aws configure set aws_access_key_id $(cat /run/secrets/AWS_ACCESS_KEY_ID); \
    aws configure set aws_secret_access_key $(cat /run/secrets/AWS_SECRET_ACCESS_KEY); \
    aws s3 sync ./public/ s3://$S3_BUCKET_NAME; \
    fi

ONBUILD RUN rm -rf node_modules vendor/bundle test
