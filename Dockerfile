# 1. Builder for Go-based tools (Fast & Reliable)
FROM golang:1.25-bookworm AS go-builder
RUN go install github.com/steipete/gogcli@latest && \
    go install github.com/yakitrak/obsidian-cli@latest && \
    go install github.com/steipete/summarize@latest && \
    go install github.com/steipete/gifgrep/cmd/gifgrep@latest && \
    go install github.com/reworkd/gemini-cli@latest

FROM node:22-bookworm

# 2. Install system essentials + ffmpeg (Static Layer)
# Using apt for ffmpeg avoids slow Homebrew source builds on ARM64
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    procps \
    sudo \
    python3 \
    python3-pip \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# 3. Set up Node user
RUN echo 'node ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
USER node

# 4. Set up Paths
# Removed linuxbrew paths to save space and speed up resolution
ENV PATH="/home/node/.bun/bin:/home/node/.local/bin:${PATH}"
ENV HOMEBREW_NO_ENV_HINTS=1
ENV HOMEBREW_NO_AUTO_UPDATE=1

# 5. Install Tool Managers (Bun & UV)
RUN curl -fsSL https://bun.sh/install | bash && \
    curl -LsSf https://astral.sh/uv/install.sh | sh

# 6. Install Go tools from builder
# We map them to the expected binary names used by the app
COPY --from=go-builder /go/bin/gogcli /home/node/.local/bin/gog
COPY --from=go-builder /go/bin/obsidian-cli /home/node/.local/bin/obsidian-cli
COPY --from=go-builder /go/bin/summarize /home/node/.local/bin/summarize
COPY --from=go-builder /go/bin/gifgrep /home/node/.local/bin/gifgrep
COPY --from=go-builder /go/bin/gemini-cli /home/node/.local/bin/gemini

# 7. Install Python tools via uv (Fast, uses pre-built wheels)
# Replacing Homebrew install with uv avoids the 1-hour build time
RUN uv tool install openai-whisper && \
    uv tool install gemini-cli

# 8. Global NPM & UV tools
RUN npm install -g clawdhub && \
    uv tool install nano-pdf

# --- START OF FREQUENTLY CHANGING LAYERS ---
USER root
RUN corepack enable
WORKDIR /app

# 7. Install Dependencies (Cached unless package.json/lock changes)
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts
RUN pnpm install --frozen-lockfile

# 8. Copy source and build (Changes every deploy)
COPY . .
RUN pnpm build && \
    pnpm ui:install && \
    pnpm ui:build

# 9. Set up Persistent Home Overlay
RUN mkdir -p /home/node/.config
RUN ln -sf /home/node/.persistent/.gitconfig /home/node/.gitconfig && \
    ln -sf /home/node/.persistent/.config/gogcli /home/node/.config/gogcli

# 10. Final Permissions & Switch User
RUN chown -R node:node /app
USER node
ENV NODE_ENV=production

CMD ["node", "dist/index.js", "gateway-daemon", "--bind", "lan", "--port", "18789", "--allow-unconfigured"]
