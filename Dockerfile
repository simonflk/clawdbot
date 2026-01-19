# 1. Builder for Go-based tools (Fast & Reliable)
FROM golang:1.25-bookworm AS go-builder
RUN apt-get update && apt-get install -y libsecret-1-dev pkg-config
RUN go install github.com/steipete/gogcli/cmd/gog@latest && \
    go install github.com/Yakitrak/obsidian-cli@latest && \
    go install github.com/steipete/gifgrep/cmd/gifgrep@latest

FROM node:22-bookworm

# 2. Install system essentials + ffmpeg + utilities (Static Layer)
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    procps \
    sudo \
    python3 \
    python3-pip \
    ffmpeg \
    poppler-utils \
    jq \
    libnss3 \
    && rm -rf /var/lib/apt/lists/*

# 3. Set up Node user (We stay root for global installs)
RUN echo 'node ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# 4. Set up Paths
ENV PATH="/home/node/.bun/bin:/home/node/.local/bin:${PATH}"
ENV HOMEBREW_NO_ENV_HINTS=1
ENV HOMEBREW_NO_AUTO_UPDATE=1

# 5. Global NPM tools (Run as root)
RUN npm install -g @steipete/summarize @google/gemini-cli clawdhub

# 6. Switch to node user
USER node

# 7. Install Tool Managers (Bun & UV) into /home/node
RUN curl -fsSL https://bun.sh/install | bash && \
    curl -LsSf https://astral.sh/uv/install.sh | sh

# 8. Install Go tools from builder
COPY --from=go-builder /go/bin/gog /home/node/.local/bin/gog
COPY --from=go-builder /go/bin/obsidian-cli /home/node/.local/bin/obsidian-cli
COPY --from=go-builder /go/bin/gifgrep /home/node/.local/bin/gifgrep

# 9. Install Python tools via uv
RUN uv tool install openai-whisper && \
    uv tool install yt-dlp && \
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
