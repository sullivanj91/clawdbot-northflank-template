# Build openclaw from source to avoid npm packaging gaps (some dist files are not shipped).
FROM node:22-bookworm AS openclaw-build

# Dependencies needed for openclaw build
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    python3 \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

# Install Bun (openclaw build uses it)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /openclaw

# Pin to a known ref (tag/branch). If it doesn't exist, fall back to main.
ARG OPENCLAW_GIT_REF=main
RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/openclaw/openclaw.git .

# Patch: relax version requirements for packages that may reference unpublished versions.
# Apply to all extension package.json files to handle workspace protocol (workspace:*).
RUN set -eux; \
  find ./extensions -name 'package.json' -type f | while read -r f; do \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
  done

RUN pnpm install --no-frozen-lockfile
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build


# Runtime image
FROM node:22-bookworm
ENV NODE_ENV=production

# Install common tooling needed by many OpenClaw skills (esp. github + coding-agent)
# - sudo: some skill installers assume it exists
# - gh: required by the github skill
# - git/ssh: required for cloning/pushing repos
# - build-essential/file/procps: common Homebrew + build deps
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    sudo \
    curl \
    git \
    openssh-client \
    gh \
    jq \
    build-essential \
    file \
    procps \
  && rm -rf /var/lib/apt/lists/*

# Install Homebrew (Linuxbrew) for runtime skill installers.
# Homebrew refuses to install as root, so we install it as an unprivileged user.
RUN useradd -m -s /bin/bash linuxbrew \
  && curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o /tmp/brew-install.sh \
  && chown linuxbrew:linuxbrew /tmp/brew-install.sh \
  && su - linuxbrew -c 'NONINTERACTIVE=1 /bin/bash /tmp/brew-install.sh' \
  && rm -f /tmp/brew-install.sh

# Bake the Homebrew shellenv into the image so `brew` works without extra login shell setup.
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew" \
    HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar" \
    HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew" \
    # Keep /usr/local/bin ahead of Linuxbrew so our /usr/local/bin/brew root-wrapper wins.
    PATH="${PATH}:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin" \
    INFOPATH="/home/linuxbrew/.linuxbrew/share/info:${INFOPATH}"

# Homebrew refuses to run as root. OpenClaw commonly runs as root in containers.
# Put a wrapper earlier on PATH so `brew ...` transparently runs as the linuxbrew user.
RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'BREW_REAL="/home/linuxbrew/.linuxbrew/bin/brew"' \
  'if [ "${EUID:-$(id -u)}" -eq 0 ]; then' \
  '  # Safely forward args into a single `su -c` string.' \
  '  args=$(printf "%q " "$@")' \
  '  cmd="eval \"$(${BREW_REAL} shellenv)\"; ${BREW_REAL} ${args}"' \
  '  exec su - linuxbrew -c "$cmd"' \
  'else' \
  '  exec "${BREW_REAL}" "$@"' \
  'fi' \
  > /usr/local/bin/brew \
  && chmod +x /usr/local/bin/brew

# Provide a coding agent binary (`pi`) so the coding-agent skill is eligible.
# (Codex OAuth is handled by OpenClaw model auth; this just supplies an interactive agent CLI.)
RUN npm install -g @mariozechner/pi-coding-agent

WORKDIR /app

# Wrapper deps
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# Copy built openclaw
COPY --from=openclaw-build /openclaw /openclaw

# Provide an openclaw executable
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
  && chmod +x /usr/local/bin/openclaw

COPY src ./src

# The wrapper listens on this port.
ENV OPENCLAW_PUBLIC_PORT=8080
ENV PORT=8080
EXPOSE 8080
CMD ["node", "src/server.js"]
