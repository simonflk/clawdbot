FROM node:22-bookworm

# 1. Install system essentials (Static Layer)
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    procps \
    sudo \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# 2. Set up Node user and Homebrew (Static Layer)
RUN echo 'node ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
USER node
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. Set up Paths
ENV PATH="/home/node/.bun/bin:/home/node/.local/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_NO_ENV_HINTS=1
ENV HOMEBREW_NO_AUTO_UPDATE=1

# 4. Install Tool Managers (Bun & UV)
RUN curl -fsSL https://bun.sh/install | bash && \
    curl -LsSf https://astral.sh/uv/install.sh | sh

# 5. Pre-install Brew formulas (Static-ish Layer)
# Grouped to reduce layer count
RUN brew tap steipete/tap && \
    brew tap yakitrak/yakitrak && \
    brew install \
    steipete/tap/gogcli \
    steipete/tap/summarize \
    steipete/tap/gifgrep \
    yakitrak/yakitrak/obsidian-cli \
    gemini-cli \
    openai-whisper

# 6. Global NPM & UV tools
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

# 9. Final Permissions & Switch User
RUN chown -R node:node /app
USER node
ENV NODE_ENV=production

CMD ["node", "dist/index.js", "gateway-daemon", "--bind", "lan", "--port", "18789", "--allow-unconfigured"]
