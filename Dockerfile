# Dyalog (ARM) Dockerfile 
FROM arm32v7/debian:bookworm-slim as installer

# Dyalog release number:
ARG DYALOG_RELEASE=19.0

# Install required packages:
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    lsb-release \
    gnupg \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Add Dyalog repository (for downloading only):
RUN echo "=== Adding Dyalog Repository ==="; \
    wget -O - https://packages.dyalog.com/dyalog-apt-key.gpg.key | apt-key add -; \
    CODENAME=$(lsb_release -sc); \
    echo "deb https://packages.dyalog.com ${CODENAME} main" | tee /etc/apt/sources.list.d/dyalog.list; \
    apt-get update

# Download and manually extract Dyalog packages (to avoid the uninterruptible license prompt in 
# the Dyalog ARM installer):
RUN set -e; \
    echo "=== Downloading and Installing Dyalog Packages ==="; \
    cd /tmp; \
    \
    # Download dyalog-unicode-190:
    echo "Downloading dyalog-unicode-190..."; \
    apt-get download dyalog-unicode-190; \
    ls -la dyalog-unicode-190*.deb; \
    DYALOG_DEB=$(ls dyalog-unicode-190*.deb | head -1); \
    echo "Extracting Dyalog main package: $DYALOG_DEB"; \
    dpkg-deb -x "$DYALOG_DEB" /tmp/extracted_dyalog; \
    cp -r /tmp/extracted_dyalog/* /; \
    echo "Dyalog main package installed"; \
    \
    # Download RIDE:
    echo "Downloading ride-4.5..."; \
    if apt-get download ride-4.5 2>/dev/null; then \
        ls -la ride-4.5*.deb; \
        RIDE_DEB=$(ls ride-4.5*.deb | head -1); \
        echo "Extracting RIDE package: $RIDE_DEB"; \
        dpkg-deb -x "$RIDE_DEB" /tmp/extracted_ride; \
        cp -r /tmp/extracted_ride/* /; \
        echo "RIDE package installed"; \
    else \
        echo "RIDE download failed (not critical)"; \
    fi; \
    \
    # Cleanup:
    rm -rf /tmp/* /var/lib/apt/lists/*

# Verify installation:
RUN echo "=== Installation Verification ==="; \
    echo "Dyalog directories:"; \
    find /opt -name "*dyalog*" -type d 2>/dev/null | head -5 || echo "No dyalog directories found"; \
    echo "Dyalog binaries:"; \
    find /opt -name "dyalog" -type f 2>/dev/null | head -3 || echo "No dyalog binaries found"; \
    echo "RIDE files:"; \
    find /opt -name "*ride*" -type f 2>/dev/null | head -3 || echo "No RIDE files found"

# Stage 2: Runtime:
FROM arm32v7/debian:bookworm-slim

ARG DYALOG_RELEASE=19.0

# Install runtime dependencies:
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    libncurses5 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i -e 's/# en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen

ENV LANG=en_GB.UTF-8 \
    LANGUAGE=en_GB:UTF-8 \
    LC_ALL=en_GB.UTF-8

# Copy installations from stage 1:
COPY --from=installer /opt /opt
COPY --from=installer /usr /usr

# Set up Dyalog alternatives:
RUN set -e; \
    echo "=== Setting up Dyalog alternatives ==="; \
    \
    # Find dyalog binary
    DYALOG_BIN=$(find /opt -name "dyalog" -type f 2>/dev/null | head -1); \
    DYALOG_SCRIPT=$(find /opt -name "dyalogscript" -type f 2>/dev/null | head -1); \
    \
    if [ -n "$DYALOG_BIN" ]; then \
        echo "Found dyalog binary: $DYALOG_BIN"; \
        P=$(echo ${DYALOG_RELEASE} | sed 's/\.//g'); \
        update-alternatives --install /usr/bin/dyalog dyalog "$DYALOG_BIN" "$P"; \
        \
        if [ -n "$DYALOG_SCRIPT" ]; then \
            echo "Found dyalogscript: $DYALOG_SCRIPT"; \
            update-alternatives --install /usr/bin/dyalogscript dyalogscript "$DYALOG_SCRIPT" "$P"; \
        fi; \
        \
        # Copy license if found
        LICENSE_FILE=$(find /opt -name "LICENSE" -type f 2>/dev/null | head -1); \
        if [ -n "$LICENSE_FILE" ]; then \
            cp "$LICENSE_FILE" /LICENSE; \
        fi; \
        \
        echo "Dyalog setup completed successfully"; \
    else \
        echo "ERROR: No dyalog binary found after installation"; \
        echo "Available files in /opt:"; \
        find /opt -type f 2>/dev/null | grep -i dyalog | head -10 || echo "No dyalog-related files found"; \
        exit 1; \
    fi

# Create user and directories:
RUN useradd -s /bin/bash -d /home/dyalog -m dyalog && \
    mkdir -p /app /storage && \
    chmod 777 /app /storage

# Copy entrypoint (starting batch script):
COPY entrypoint /entrypoint
RUN chmod +x /entrypoint

LABEL org.label-schema.licence="proprietary / non-commercial" \
      org.label-schema.licenceURL="https://www.dyalog.com/uploads/documents/Private_Personal_Educational_Licence.pdf"

EXPOSE 4502
USER dyalog
WORKDIR /home/dyalog
VOLUME ["/storage", "/app"]

ENTRYPOINT ["/entrypoint"]
