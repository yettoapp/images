# repeated below, because Docker
ARG PG_VERSION_MAJOR=17
ARG DEBIAN_VERSION="bookworm"

############################################
# First Stage: Builder
############################################

FROM postgres:${PG_VERSION_MAJOR}-${DEBIAN_VERSION} AS builder

# repeated above, because Docker
ARG PG_VERSION_MAJOR=17
ARG DEBIAN_VERSION="bookworm"

ARG RUST_VERSION=1.81.0
ARG PGRX_VERSION=0.12.7
ARG PGX_ULID_VERSION=0.2.0
ARG PGVECTOR_VERSION=0.7.2

# Declare buildtime environment variables
ENV DEBIAN_VERSION="noninteractive" \
    PG_VERSION_MAJOR=${PG_VERSION_MAJOR} \
    RUST_VERSION=${RUST_VERSION} \
    PGRX_VERSION=${PGRX_VERSION} \
    PGX_ULID_VERSION=${PGX_ULID_VERSION} \
    PGVECTOR_VERSION=${PGVECTOR_VERSION}

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    ca-certificates \
    git \
    build-essential \
    checkinstall \
    libpq-dev \
    postgresql-server-dev-${PG_VERSION_MAJOR} \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path --profile minimal --default-toolchain ${RUST_VERSION}

# Install pgrx
RUN $HOME/.cargo/bin/cargo install cargo-pgrx --version "${PGRX_VERSION}" --locked
RUN $HOME/.cargo/bin/cargo pgrx init --pg${PG_VERSION_MAJOR} $(which pg_config)

###################
# pgx_ulid
###################

FROM builder AS builder-pgx_ulid

# Download the extension
WORKDIR /tmp
RUN curl -L -o pgx_ulid.deb "https://github.com/pksunkara/pgx_ulid/releases/download/v${PGX_ULID_VERSION}/pgx_ulid-v${PGX_ULID_VERSION}-pg${PG_VERSION_MAJOR}-amd64-linux-gnu.deb"

###################
# pgvector
###################

FROM builder AS builder-pgvector

WORKDIR /tmp

# Download and extract the pgvector release
RUN curl -L -o pgvector.tar.gz "https://github.com/pgvector/pgvector/archive/refs/tags/v${PGVECTOR_VERSION}.tar.gz" && \
    mkdir -p /tmp/pgvector && \
    tar -xvf pgvector.tar.gz --strip-components=1 -C /tmp/pgvector && \
    cd /tmp/pgvector && \
    make OPTFLAGS="" "-j$(nproc)" && \
    checkinstall -D --nodoc --install=no --fstrans=no --backup=no --pakdir=/tmp

###############################################
# Second Stage: PostgreSQL
###############################################

FROM postgres:${PG_VERSION_MAJOR}-${DEBIAN_VERSION}

ARG PG_VERSION_MAJOR
ARG PGX_ULID_VERSION

# Copy the compiled pgx_ulid extension from the builder stage
COPY --from=builder-pgx_ulid /tmp/pgx_ulid.deb /tmp
# unsure why but `PGX_ULID_VERSION` is unavailable, so we'll do it the long way
RUN dpkg -i /tmp/pgx_ulid.deb && rm /tmp/pgx_ulid.deb && \
    mv /usr/share/postgresql/${PG_VERSION_MAJOR}/extension/ulid.control /usr/share/postgresql/${PG_VERSION_MAJOR}/extension/pgx_ulid.control && \
    for file in /usr/share/postgresql/${PG_VERSION_MAJOR}/extension/ulid--*.sql; do \
    mv "$file" "/usr/share/postgresql/${PG_VERSION_MAJOR}/extension/pgx_ulid--${file##*--}"; \
    done

# Copy the compiled pgvector extension from the builder stage
COPY --from=builder-pgvector /tmp/pgvector*.deb /tmp
RUN dpkg -i /tmp/pgvector*.deb && rm /tmp/pgvector*.deb

# Clean up build dependencies and temporary files
RUN apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp

# Configure shared_preload_libraries
RUN echo "ALTER SYSTEM SET shared_preload_libraries = 'pgx_ulid';\n\
    CREATE EXTENSION IF NOT EXISTS pgx_ulid;\n" > /docker-entrypoint-initdb.d/01-init.sql

USER postgres

# Variables needed at runtime to configure postgres and run the initdb scripts
ENV POSTGRES_USER=billy

# Note: This is overriden by passing the POSTGRESQL_PASSWORD environment
# variable via `docker-compose` or `docker run -e POSTGRESQL_PASSWORD`. All production usage
# uses a unique, secure password and does not rely on the default settings.
ENV POSTGRES_PASSWORD=marxvanzetti
