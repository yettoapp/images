# version of 1Password CLI to install
ARG OPASSWORD_VERSION=2.30.3

FROM 1password/op:${OPASSWORD_VERSION} AS op

# Copy built artifacts
ONBUILD COPY --from=tailscale /app/tailscaled /app/tailscaled
ONBUILD COPY --from=tailscale /app/tailscale /app/tailscale
ONBUILD RUN mkdir -p /var/run/tailscale /var/cache/tailscale /app/.cache /app/.local
