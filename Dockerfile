FROM node:22-bookworm

# 1. Install build essentials and core dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    procps \
    sudo \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Arguments for extra packages if needed
ARG CLAWDBOT_DOCKER_APT_PACKAGES=""
RUN if [ -n "$CLAWDBOT_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $CLAWDBOT_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# 2. Install Homebrew as the 'node' user
RUN echo 'node ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
USER node
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. Set up Paths (Homebrew, Bun, etc.)
ENV PATH="/home/node/.bun/bin:/home/node/.local/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_NO_ENV_HINTS=1
ENV HOMEBREW_NO_AUTO_UPDATE=1

# 4. Install Bun and UV (standard for python-based skills like nano-pdf/nano-banana)
RUN curl -fsSL https://bun.sh/install | bash
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# 5. Pre-install Brew formulas for requested skills
# Skills covered: gog, summarize, obsidian-cli, gemini, gifgrep, openai-whisper
RUN brew tap steipete/tap && \
    brew tap yakitrak/yakitrak && \
    brew install \
    steipete/tap/gogcli \
    steipete/tap/summarize \
    steipete/tap/gifgrep \
    yakitrak/yakitrak/obsidian-cli \
    gemini-cli \
    openai-whisper

# 6. Pre-install Global NPM packages
# Skills covered: clawdhub
RUN npm install -g clawdhub

# 7. Pre-install UV packages
# Skills covered: nano-pdf
RUN uv tool install nano-pdf

# Switch back to root to set up the app directory
USER root
RUN corepack enable
WORKDIR /app

# 8. Build process
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build
RUN pnpm ui:install
RUN pnpm ui:build

# 9. Final Permissions & Switch User
RUN chown -R node:node /app
USER node
ENV NODE_ENV=production

# The home directory for the 'node' user is /home/node
# IMPORTANT: Ensure your Coolify mounts point to /home/node/.clawdbot
CMD ["node", "dist/index.js", "gateway-daemon", "--bind", "lan", "--port", "18789", "--allow-unconfigured"]
