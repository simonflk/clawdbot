FROM node:22-bookworm

# Install build essentials and dependencies for Homebrew
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    procps \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Install Homebrew as a non-root user (Homebrew refuses to install as root)
RUN useradd -m -s /bin/bash linuxbrew && \
    echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
USER linuxbrew
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Switch back to root for the rest of the build
USER root
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_NO_ENV_HINTS=1
ENV HOMEBREW_NO_AUTO_UPDATE=1

RUN corepack enable

WORKDIR /app

# Arguments for extra packages if needed
ARG CLAWDBOT_DOCKER_APT_PACKAGES=""
RUN if [ -n "$CLAWDBOT_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $CLAWDBOT_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build
RUN pnpm ui:install
RUN pnpm ui:build

ENV NODE_ENV=production

CMD ["node", "dist/index.js", "gateway-daemon", "--bind", "lan", "--port", "18789", "--allow-unconfigured"]
