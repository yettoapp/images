# version of tailscale to install
ARG TAILSCALE_VERSION=1.76.6

FROM tailscale/tailscale:v${TAILSCALE_VERSION} AS tailscale

# Copy built artifacts
ONBUILD COPY --from=tailscale /app/tailscaled /app/tailscaled
ONBUILD COPY --from=tailscale /app/tailscale /app/tailscale
ONBUILD RUN mkdir -p /var/run/tailscale /var/cache/tailscale /app/.cache /app/.local
