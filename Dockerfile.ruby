# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.3.0
# Node version to use in base image
ARG NODE_VERSION=20.10.0

# Debian image to use for base images
ARG DEBIAN_VERSION="bookworm"
# Node image to use for base images
FROM docker.io/node:${NODE_VERSION}-${DEBIAN_VERSION}-slim as node
# Ruby image to use for base image
FROM docker.io/ruby:${RUBY_VERSION}-slim-${DEBIAN_VERSION} as ruby

# Apply timezone
ENV TZ="Etc/UTC"
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

ENV LANG=C.UTF-8

# Linux UID (user id) for the yetto user
ARG UID="666"
# Linux GID (group id) for the yetto user
ARG GID="666"

ARG RAILS_ENV
# Set environment for Ruby on Rails
ENV RAILS_ENV=${RAILS_ENV:-development}
# Use environment for Node; can (and does_ change in production)
ENV NODE_ENV=${RAILS_ENV:-development}

ARG GIT_SHA
ENV GIT_SHA=$GIT_SHA

# version of tailscale to install
ENV TAILSCALE_VERSION=1.54.0

# version of AWS CLI to install
ENV AWSCLI_VERSION=2.14.3

# version of OpenTelemetry Collector to install
ENV OTEL_COLLECTOR_VERSION=0.91.0
# OTEL specific env vars, for both the app and the collector
ARG HONEYCOMB_API_KEY
ENV HONEYCOMB_API_KEY=${HONEYCOMB_API_KEY}

# establish the environment for OTEL
ENV OTEL_EXPORTER_OTLP_ENDPOINT="https://api.honeycomb.io"
ENV OTEL_EXPORTER_OTLP_HEADERS="x-honeycomb-team=${HONEYCOMB_API_KEY}"
ENV OTEL_SERVICE_NAME="yetto-${RAILS_ENV}"

ARG FLY_METRICS_TOKEN
ENV FLY_METRICS_TOKEN=${FLY_METRICS_TOKEN}

ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ARG S3_BUCKET_NAME
ARG AWS_DEFAULT_REGION
ENV AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
ENV AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
ENV S3_BUCKET_NAME=${S3_BUCKET_NAME}
ENV AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}

ENV \
    RAILS_LOG_TO_STDOUT="1" \
    RAILS_SERVE_STATIC_FILES="true" \
    DEBIAN_FRONTEND="noninteractive" \
    PATH="${PATH}:/opt/ruby/bin:/yetto/bin" \
    MALLOC_CONF="narenas:2,background_thread:true,thp:never,dirty_decay_ms:1000,muzzy_decay_ms:0"

# Set default shell used for running commands
SHELL ["/bin/bash", "-o", "pipefail", "-o", "errexit", "-c"]

USER root

RUN \
    # Remove automatic apt cache Docker cleanup scripts
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    # Creates yetto user/group and sets home directory
    groupadd --gid "${GID}" --system yetto; \
    useradd --uid "${UID}" --gid yetto --no-create-home --system yetto;

# Rails app lives here
WORKDIR /yetto

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
    cmake \
    gnupg2 \
    curl \
    unzip \
    less \
    git \
    # Install jemalloc
    libjemalloc2 \
    patchelf \
    ; \
    # Patch Ruby to use jemalloc
    patchelf --add-needed libjemalloc.so.2 /usr/local/bin/ruby; \
    # Discard patchelf after use
    apt-get purge -y \
    patchelf \
    ;


FROM ruby as prebuild

ARG AWSCLI_VERSION

COPY --from=node /usr/local/bin /usr/local/bin
COPY --from=node /usr/local/lib /usr/local/lib

COPY package.json package-lock.json /yetto/

# Install packages needed to build gems and node modules
RUN --mount=type=cache,id=apt-cache-${RAILS_ENV},sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=apt-lib-${RAILS_ENV},sharing=locked,target=/var/lib/apt \
    # Have to run update here I think :thinking:
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    libpq-dev \
    node-gyp \
    pkg-config \
    python-is-python3 \
    ca-certificates \
    iptables \
    iproute2 \
    ;

# Install AWS CLI
RUN if [[ "$RAILS_ENV" = "production" && "$AWS_ACCESS_KEY_ID" != "" && "$AWS_SECRET_ACCESS_KEY" != "" ]]; then \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install; \
    fi


FROM prebuild as bundler

ARG RAILS_ENV

# Copy Gemfile config into working directory
COPY Gemfile* .ruby-version /yetto/

RUN \
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
    # Upgrade RubyGems
    gem update --system; \
    # Download and install required Gems
    bundle install -j"$(nproc)";


FROM prebuild as npm

ARG NODE_ENV

# Copy Node package configuration files into working directory
COPY package.json package-lock.json /yetto/

RUN \
    --mount=type=cache,id=npm-cache-${NODE_ENV},target=/root/.npm,sharing=locked \
    npm ci

# Install Tailscale
FROM prebuild as tailscale
WORKDIR /yetto

ARG TAILSCALE_VERSION
RUN curl -L -o "tailscale_${TAILSCALE_VERSION}_amd64.tgz" https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_amd64.tgz && \
    tar xzf "tailscale_${TAILSCALE_VERSION}_amd64.tgz" --strip-components=1

# Install OpenTelemetry Collector
FROM prebuild as opentelemetry

ARG OTEL_COLLECTOR_VERSION
RUN curl -L -o "otelcol.tar.gz" https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_COLLECTOR_VERSION}/otelcol-contrib_${OTEL_COLLECTOR_VERSION}_linux_amd64.tar.gz && \
    mkdir otelcol-contrib && \
    tar xfz "otelcol.tar.gz" -C otelcol-contrib && \
    chmod +x otelcol-contrib

# Create temporary assets build layer from build layer
FROM prebuild as assets

ARG RAILS_ENV
ARG AWS_ACCESS_KEY_ID=""
ARG AWS_SECRET_ACCESS_KEY=""
ARG S3_BUCKET_NAME

# Copy Yetto sources into precompiler layer
COPY . /yetto

# Copy node and bundler dependencies from prebuild layer
COPY --from=npm /yetto /yetto
COPY --from=bundler /yetto /yetto
COPY --from=bundler /usr/local/bundle/ /usr/local/bundle/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN <<BASH
  set -ex

  # for postcss, etc
  NODE_ENV=development npm install
  RAILS_ENV=production PRECOMPILING=1 SECRET_KEY_BASE=DUMMY bin/rails assets:precompile
  rm -fr /yetto/tmp;
BASH

# Upload assets to S3
RUN if [[ "$RAILS_ENV" = "production" && "$AWS_ACCESS_KEY_ID" != "" && "$AWS_SECRET_ACCESS_KEY" != "" ]]; then \
    aws configure set aws_access_key_id ${AWS_ACCESS_KEY_ID}; \
    aws configure set aws_secret_access_key ${AWS_SECRET_ACCESS_KEY}; \
    aws s3 sync ./public/ s3://${S3_BUCKET_NAME}; \
    fi

# Final stage for app image
FROM ruby as yetto

ARG RAILS_ENV
ARG GIT_SHA

RUN \
    # Mount Apt cache and lib directories from Docker buildx caches
    --mount=type=cache,id=apt-cache-${RAILS_ENV},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib-${RAILS_ENV},target=/var/lib/apt,sharing=locked \
    # Mount NPM caches from Docker buildx caches
    --mount=type=cache,id=npm-cache-${RAILS_ENV},target=/root/.npm,sharing=locked \
    apt-get update -qq && \
    # Install packages needed for deployment
    apt-get install --no-install-recommends -y postgresql-client sudo cron vim \
    ;

# Copy Yetto sources into final layer
COPY . /yetto

# Copy compiled assets to layer
COPY --from=assets /yetto/public/ /yetto/public/
# Copy bundler components to layer
COPY --from=bundler /usr/local/bundle/ /usr/local/bundle/

# Copy other built artifacts
COPY --from=tailscale /yetto/tailscaled /yetto/tailscaled
COPY --from=tailscale /yetto/tailscale /yetto/tailscale
RUN mkdir -p /var/run/tailscale /var/cache/tailscale /yetto/.cache /yetto/.local

COPY --from=opentelemetry /yetto/otelcol-contrib /usr/local/bin/

RUN \
    # Set Yetto user as owner of log folder
    chown -R yetto:yetto /yetto/log; \
    # Set Yetto user as owner of tmp folder
    mkdir -p /yetto/tmp; \
    chown -R yetto:yetto /yetto/tmp;

RUN \
    # Write latest crontab
    bundle exec whenever --update-crontab && \
    # Pass build version
    echo $GIT_SHA > /yetto/GIT_SHA

RUN \
    # Precompile bootsnap code for faster Rails startup
    bundle exec bootsnap precompile --gemfile app/ lib/;

USER yetto

# Entrypoint sets up the container.
ENTRYPOINT ["/yetto/bin/docker-entrypoint"]

# Expose default Puma ports
EXPOSE 3000

# Start the server
CMD ["./bin/rails", "server"]
