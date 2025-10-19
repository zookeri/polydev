
# Multi-stage build for better optimization
FROM ubuntu:24.04

# Build arguments for multi-architecture support
ARG TARGETOS
ARG TARGETARCH

# Environment variables
ENV LANG="C.UTF-8"
ENV HOME=/root
ENV DEBIAN_FRONTEND=noninteractive

# Stage 1: Base system dependencies
FROM ubuntu:24.04 AS base

# Install essential system packages and development tools
# Ordered by priority: system -> build tools -> development libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    # System utilities
    sudo=1.9.* \
    curl=8.5.* \
    wget=1.21.* \
    gnupg=2.4.* \
    software-properties-common=0.99.* \
    tzdata=2025b-* \
    # Core build tools
    build-essential=12.10* \
    make=4.3-* \
    cmake=3.28.* \
    pkg-config=1.8.* \
    ninja-build=1.11.* \
    # Version control systems
    git=1:2.43.* \
    git-lfs=3.4.* \
    bzr=2.7.* \
    # Network utilities
    dnsutils=1:9.18.* \
    iputils-ping=3:20240117-* \
    netcat-openbsd=1.226-* \
    openssh-client=1:9.6p1-* \
    rsync=3.2.* \
    # Compression and archiving
    unzip=6.0-* \
    zip=3.0-* \
    xz-utils=5.6.* \
    # System libraries
    libc6=2.39-* \
    libc6-dev=2.39-* \
    libgcc-13-dev=13.3.* \
    libstdc++-13-dev=13.3.* \
    libunwind8=1.6.* \
    libuuid1=2.39.* \
    zlib1g=1:1.3.* \
    zlib1g-dev=1:1.3.* \
    # Development libraries (alphabetical)
    libbz2-dev=1.0.* \
    libcurl4-openssl-dev=8.5.* \
    libdb-dev=1:5.3.* \
    libedit2=3.1-* \
    libffi-dev=3.4.* \
    libgdbm-dev=1.23-* \
    libgdbm-compat-dev=1.23-* \
    libgdiplus=6.1+dfsg-* \
    libgssapi-krb5-2=1.20.* \
    liblzma-dev=5.6.* \
    libncurses-dev=6.4+20240113-* \
    libnss3-dev=2:3.98-* \
    libpq-dev=16.9-* \
    libpsl-dev=0.21.* \
    libpython3-dev=3.12.* \
    libreadline-dev=8.2-* \
    libsqlite3-dev=3.45.* \
    libssl-dev=3.0.* \
    libxml2-dev=2.9.* \
    libz3-dev=4.8.* \
    # Database clients
    default-libmysqlclient-dev=1.1.* \
    sqlite3=3.45.* \
    unixodbc-dev=2.3.* \
    uuid-dev=2.39.* \
    # Text processing
    gettext=0.21-* \
    jq=1.7.* \
    moreutils=0.69-* \
    ripgrep=14.1.* \
    # Monitoring tools
    inotify-tools=3.22.* \
    # Assembly compilers
    nasm=2.16.* \
    yasm=1.3.* \
    # Other utilities
    binutils=2.42-* \
    ccache=4.9.* \
    gawk=1:5.2.* \
    lsb-release=12.0-* \
    protobuf-compiler=3.21.* \
    swig3.0=3.0.* \
    tk-dev=8.6.* \
    && rm -rf /var/lib/apt/lists/*

# Stage 2: QEMU and multi-architecture support
FROM base AS qemu

# Install QEMU for cross-architecture emulation
RUN apt-get update && apt-get install -y --no-install-recommends \
    qemu-user-static \
    binfmt-support \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && update-binfmts --enable qemu-${TARGETARCH} \
    && echo "QEMU setup completed for architecture: $TARGETARCH"

# Stage 3: Runtime manager (Mise)
FROM qemu AS mise

# Install Mise for version management
RUN install -dm 0755 /etc/apt/keyrings \
    && curl -fsSL https://mise.jdx.dev/gpg-key.pub | gpg --batch --yes --dearmor -o /etc/apt/keyrings/mise-archive-keyring.gpg \
    && chmod 0644 /etc/apt/keyrings/mise-archive-keyring.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg] https://mise.jdx.dev/deb stable main" > /etc/apt/sources.list.d/mise.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mise/stable \
    && rm -rf /var/lib/apt/lists/* \
    && echo 'eval "$(mise activate bash)"' >> /etc/profile \
    && mise settings set experimental true \
    && mise settings set override_tool_versions_filenames none \
    && mise settings add idiomatic_version_file_enable_tools "[]"

ENV PATH=$HOME/.local/share/mise/shims:$PATH

# Stage 4: Compiler toolchain
FROM mise AS compilers

# Install LLVM toolchain
RUN bash -c "$(curl -fsSL https://apt.llvm.org/llvm.sh)"

# Stage 5: Python ecosystem
FROM compilers AS python

ARG PYENV_VERSION=v2.5.5
ARG PYTHON_VERSIONS="3.11.12 3.10 3.12 3.13"

# Install pyenv and multiple Python versions
ENV PYENV_ROOT=/root/.pyenv
ENV PATH=$PYENV_ROOT/bin:$PATH
RUN git -c advice.detachedHead=0 clone --branch "$PYENV_VERSION" --depth 1 https://github.com/pyenv/pyenv.git "$PYENV_ROOT" \
    && echo 'export PYENV_ROOT="$HOME/.pyenv"' >> /etc/profile \
    && echo 'export PATH="$PYENV_ROOT/shims:$PYENV_ROOT/bin:$PATH"' >> /etc/profile \
    && echo 'eval "$(pyenv init - bash)"' >> /etc/profile \
    && cd "$PYENV_ROOT" \
    && src/configure \
    && make -C src \
    && pyenv install $PYTHON_VERSIONS \
    && pyenv global "${PYTHON_VERSIONS%% *}" \
    && rm -rf "$PYENV_ROOT/cache"

# Install pipx and Python tooling
ENV PIPX_BIN_DIR=/root/.local/bin
ENV PATH=$PIPX_BIN_DIR:$PATH
RUN apt-get update \
    && apt-get install -y --no-install-recommends pipx=1.4.* \
    && rm -rf /var/lib/apt/lists/* \
    && pipx install --pip-args="--no-cache-dir --no-compile" poetry==2.1.* uv==0.7.* \
    && for pyv in "${PYENV_ROOT}/versions/"*; do \
         "$pyv/bin/python" -m pip install --no-cache-dir --no-compile --upgrade pip && \
         "$pyv/bin/pip" install --no-cache-dir --no-compile ruff black mypy pyright isort pytest; \
       done \
    && rm -rf /root/.cache/pip ~/.cache/pip ~/.cache/pipx

# Optimize uv performance
ENV UV_NO_PROGRESS=1

# Stage 6: JavaScript/TypeScript ecosystem
FROM python AS javascript

ARG NVM_VERSION=v0.40.2
ARG NODE_VERSION=22

ENV NVM_DIR=/root/.nvm
ENV COREPACK_DEFAULT_TO_LATEST=0
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
ENV COREPACK_ENABLE_AUTO_PIN=0
ENV COREPACK_ENABLE_STRICT=0

# Install Node.js versions and package managers
RUN git -c advice.detachedHead=0 clone --branch "$NVM_VERSION" --depth 1 https://github.com/nvm-sh/nvm.git "$NVM_DIR" \
    && echo 'source $NVM_DIR/nvm.sh' >> /etc/profile \
    && echo "prettier\neslint\ntypescript" > $NVM_DIR/default-packages \
    && . $NVM_DIR/nvm.sh \
    && nvm install 18 && nvm use 18 && npm install -g npm@10.9 pnpm@10.12 && corepack enable && corepack install -g yarn \
    && nvm install 20 && nvm use 20 && npm install -g npm@11.4 pnpm@10.12 && corepack enable && corepack install -g yarn \
    && nvm install 22 && nvm use 22 && npm install -g npm@11.4 pnpm@10.12 && corepack enable && corepack install -g yarn \
    && nvm alias default "$NODE_VERSION"

# Stage 7: Bun runtime
FROM javascript AS bun

ARG BUN_VERSION=1.2.14
RUN mise use --global "bun@${BUN_VERSION}" \
    && mise cache clear || true \
    && rm -rf "$HOME/.cache/mise" "$HOME/.local/share/mise/downloads"

# Stage 8: Java ecosystem
FROM bun AS java

ARG GRADLE_VERSION=8.14
ARG MAVEN_VERSION=3.9.10
ARG AMD_JAVA_VERSIONS="21 17 11"
ARG ARM_JAVA_VERSIONS="21 17"

# Install Java versions and build tools
RUN JAVA_VERSIONS="$( [ "$TARGETARCH" = "arm64" ] && echo "$ARM_JAVA_VERSIONS" || echo "$AMD_JAVA_VERSIONS" )" \
    && for v in $JAVA_VERSIONS; do mise install "java@${v}"; done \
    && mise use --global "java@${JAVA_VERSIONS%% *}" \
    && mise use --global "gradle@${GRADLE_VERSION}" \
    && mise use --global "maven@${MAVEN_VERSION}" \
    && mise cache clear || true \
    && rm -rf "$HOME/.cache/mise" "$HOME/.local/share/mise/downloads"

# Stage 9: Swift (AMD64 only)
FROM java AS swift

ARG SWIFT_VERSIONS="6.1 5.10.1"
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      for v in $SWIFT_VERSIONS; do \
        mise install "swift@${v}"; \
      done && \
      mise use --global "swift@${SWIFT_VERSIONS%% *}" \
      && mise cache clear || true \
      && rm -rf "$HOME/.cache/mise" "$HOME/.local/share/mise/downloads"; \
    else \
      echo "Skipping Swift install on $TARGETARCH"; \
    fi

# Stage 10: Rust toolchain
FROM swift AS rust

ARG RUST_VERSIONS="1.89.0 1.88.0 1.87.0 1.86.0 1.85.1 1.84.1 1.83.0"

# Install Rust and toolchains
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain none \
    && . "$HOME/.cargo/env" \
    && echo 'source $HOME/.cargo/env' >> /etc/profile \
    && rustup toolchain install $RUST_VERSIONS --profile minimal --component rustfmt --component clippy \
    && rustup default ${RUST_VERSIONS%% *}

# Stage 11: Ruby ecosystem
FROM rust AS ruby

ARG RUBY_VERSIONS="3.2.3 3.3.8 3.4.4"

# Install Ruby dependencies and versions
RUN apt-get update && apt-get install -y --no-install-recommends \
    libyaml-dev=0.2.* \
    libgmp-dev=2:6.3.* \
    && rm -rf /var/lib/apt/lists/* \
    && for v in $RUBY_VERSIONS; do mise install "ruby@${v}"; done \
    && mise use --global "ruby@${RUBY_VERSIONS%% *}" \
    && mise cache clear || true \
    && rm -rf "$HOME/.cache/mise" "$HOME/.local/share/mise/downloads"

# Stage 12: C++ tooling
FROM ruby AS cpp

# Install C++ linters and formatters
RUN pipx install --pip-args="--no-cache-dir --no-compile" cpplint==2.0.* clang-tidy==20.1.* clang-format==20.1.* cmakelang==0.6.* \
    && rm -rf /root/.cache/pip ~/.cache/pip ~/.cache/pipx

# Stage 13: Bazel build system
FROM cpp AS bazel

ARG BAZELISK_VERSION=v1.26.0

# Install Bazel via Bazelisk
RUN curl -L --fail https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-${TARGETOS}-${TARGETARCH} -o /usr/local/bin/bazelisk \
    && chmod +x /usr/local/bin/bazelisk \
    && ln -s /usr/local/bin/bazelisk /usr/local/bin/bazel

# Stage 14: Go ecosystem
FROM bazel AS golang

ARG GO_VERSIONS="1.24.3 1.23.8 1.22.12"
ARG GOLANG_CI_LINT_VERSION=2.1.6

ENV PATH=/usr/local/go/bin:$HOME/go/bin:$PATH

# Install Go versions and tools
RUN for v in $GO_VERSIONS; do mise install "go@${v}"; done \
    && mise use --global "go@${GO_VERSIONS%% *}" \
    && mise use --global "golangci-lint@${GOLANG_CI_LINT_VERSION}" \
    && mise cache clear || true \
    && rm -rf "$HOME/.cache/mise" "$HOME/.local/share/mise/downloads"

# Stage 15: PHP ecosystem
FROM golang AS php

ARG PHP_VERSIONS="8.4 8.3 8.2"
ARG COMPOSER_ALLOW_SUPERUSER=1

# Install PHP dependencies and versions
RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf=2.71-* \
    bison=2:3.8.* \
    libgd-dev=2.3.* \
    libedit-dev=3.1-* \
    libicu-dev=74.2-* \
    libjpeg-dev=8c-* \
    libonig-dev=6.9.* \
    libpng-dev=1.6.* \
    libpq-dev=16.9-* \
    libzip-dev=1.7.* \
    openssl=3.0.* \
    re2c=3.1-* \
    && rm -rf /var/lib/apt/lists/* \
    && for v in $PHP_VERSIONS; do mise install "php@${v}"; done \
    && mise use --global "php@${PHP_VERSIONS%% *}" \
    && mise cache clear || true \
    && rm -rf "$HOME/.cache/mise" "$HOME/.local/share/mise/downloads"

# Stage 16: Elixir/Erlang ecosystem
FROM php AS elixir

ARG ERLANG_VERSION=27.1.2
ARG ELIXIR_VERSION=1.18.3

# Install Erlang and Elixir
RUN mise install "erlang@${ERLANG_VERSION}" "elixir@${ELIXIR_VERSION}-otp-27" \
    && mise use --global "erlang@${ERLANG_VERSION}" "elixir@${ELIXIR_VERSION}-otp-27" \
    && mise cache clear || true \
    && rm -rf "$HOME/.cache/mise" "$HOME/.local/share/mise/downloads"

# Final stage: Application setup
FROM elixir AS final

# Copy setup scripts
COPY setup_universal.sh /opt/polydev/universal.sh
RUN chmod +x /opt/polydev/universal.sh

# Copy verification script
COPY verify.sh /opt/verify.sh
RUN chmod +x /opt/verify.sh && bash -lc "TARGETARCH=$TARGETARCH /opt/verify.sh"

# Copy entrypoint script
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/opt/entrypoint.sh"]

