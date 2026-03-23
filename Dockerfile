# =============================================================================
# SaG4n Dockerfile
# - Downloads and builds Geant4
# - Downloads Geant4 datasets during build
# - Downloads and builds SaG4n source
# - Downloads JENDLTENDL01 (alpha,xn) data library
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Build Geant4 with datasets
# -----------------------------------------------------------------------------
FROM ubuntu:22.04 AS geant4-builder

ARG DEBIAN_FRONTEND=noninteractive
ARG GEANT4_VERSION=11.4.0
ARG G4INSTALL=/opt/geant4

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    wget \
    ca-certificates \
    libx11-dev \
    libxmu-dev \
    libmotif-dev \
    libxext-dev \
    libexpat1-dev \
    libxerces-c-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/geant4-build && \
    cd /tmp/geant4-build && \
    wget --no-verbose https://github.com/Geant4/geant4/archive/v${GEANT4_VERSION}.tar.gz && \
    tar -xzf v${GEANT4_VERSION}.tar.gz && \
    mkdir -p build && \
    cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=${G4INSTALL} \
          -DCMAKE_BUILD_TYPE=Release \
          -DGEANT4_USE_GDML=ON \
          -DGEANT4_USE_SYSTEM_EXPAT=ON \
          -DGEANT4_BUILD_MULTITHREADED=ON \
          -DGEANT4_INSTALL_DATA=ON \
          -DCMAKE_CXX_FLAGS="-O3" \
          ../geant4-${GEANT4_VERSION} && \
    cmake --build . --parallel $(nproc) && \
    cmake --install . && \
    sed -i -E \
      -e 's@^# (export G4NEUTRONHPDATA=.*)@\1@' \
      -e 's@^# (export G4LEDATA=.*)@\1@' \
      -e 's@^# (export G4LEVELGAMMADATA=.*)@\1@' \
      -e 's@^# (export G4RADIOACTIVEDATA=.*)@\1@' \
      -e 's@^# (export G4PARTICLEXSDATA=.*)@\1@' \
      -e 's@^# (export G4PIIDATA=.*)@\1@' \
      -e 's@^# (export G4REALSURFACEDATA=.*)@\1@' \
      -e 's@^# (export G4SAIDXSDATA=.*)@\1@' \
      -e 's@^# (export G4ABLADATA=.*)@\1@' \
      -e 's@^# (export G4INCLDATA=.*)@\1@' \
      -e 's@^# (export G4ENSDFSTATEDATA=.*)@\1@' \
      -e 's@^# (export G4CHANNELINGDATA=.*)@\1@' \
      ${G4INSTALL}/bin/geant4.sh && \
    test -f ${G4INSTALL}/share/Geant4/geant4make/geant4make.sh && \
    test -d ${G4INSTALL}/share/Geant4/data && \
    rm -rf /tmp/geant4-build

# -----------------------------------------------------------------------------
# Stage 2: Build SaG4n and fetch JENDLTENDL01
# -----------------------------------------------------------------------------
FROM geant4-builder AS sag4n-builder

ARG DEBIAN_FRONTEND=noninteractive
ARG G4INSTALL=/opt/geant4
ARG SAG4N_TAG=v1.5
ARG SAG4N_SRC_URL=https://codeload.github.com/UIN-CIEMAT/SaG4n/tar.gz/refs/tags/${SAG4N_TAG}
ARG SAG4N_DATA_URL=https://cernbox.cern.ch/remote.php/dav/public-files/JBBzfqj4RVFjxL7/JENDLTENDL01.tar.gz

RUN mkdir -p /opt/sag4n && \
    cd /opt/sag4n && \
    wget --no-verbose -O SaG4n.tar.gz "${SAG4N_SRC_URL}" && \
    tar -xzf SaG4n.tar.gz && \
    src_dir=$(find . -maxdepth 1 -type d -name 'SaG4n-*' | head -n 1) && \
    mv "${src_dir}" SaG4n && \
    rm -f SaG4n.tar.gz

RUN mkdir -p /opt/sag4n/data && \
    cd /opt/sag4n/data && \
    wget --no-verbose -O JENDLTENDL01.tar.gz "${SAG4N_DATA_URL}" && \
    tar -xzf JENDLTENDL01.tar.gz && \
    test -d /opt/sag4n/data/JENDLTENDL01

RUN cd /opt/sag4n && \
    mkdir -p build && \
    cd build && \
    . ${G4INSTALL}/share/Geant4/geant4make/geant4make.sh && \
    cmake -DGeant4_DIR=${G4INSTALL}/lib/cmake/Geant4 \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_CXX_FLAGS="-O3" \
          ../SaG4n && \
    cmake --build . --parallel $(nproc) && \
    test -f /opt/sag4n/build/SaG4n && \
    mkdir -p /opt/sag4n/install/bin && \
    cp /opt/sag4n/build/SaG4n /opt/sag4n/install/bin/SaG4n

# -----------------------------------------------------------------------------
# Stage 3: Runtime image
# -----------------------------------------------------------------------------
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG G4INSTALL=/opt/geant4

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    libx11-6 \
    libxmu6 \
    libxm4 \
    libxext6 \
    libexpat1 \
    libxerces-c3.2 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=geant4-builder ${G4INSTALL} ${G4INSTALL}
COPY --from=sag4n-builder /opt/sag4n/install /opt/sag4n/install
COPY --from=sag4n-builder /opt/sag4n/data /opt/sag4n/data

# Geant4 dataset variables are initialized at runtime by sourcing geant4.sh.
ENV GEANT4_DATA_DIR=${G4INSTALL}/share/Geant4/data
ENV G4PARTICLEHPDATA=/opt/sag4n/data/JENDLTENDL01

ENV PATH=/opt/sag4n/install/bin:${PATH}
ENV LD_LIBRARY_PATH=${G4INSTALL}/lib:${LD_LIBRARY_PATH}

RUN test -f /opt/sag4n/install/bin/SaG4n && \
    test -d /opt/sag4n/data/JENDLTENDL01 && \
    test -d ${GEANT4_DATA_DIR}

RUN cat <<'EOF' > /usr/local/bin/sag4n-entrypoint && chmod +x /usr/local/bin/sag4n-entrypoint
#!/usr/bin/env bash
set -euo pipefail

# geant4.sh exports the correct dataset variables for the installed dataset versions.
# shellcheck source=/dev/null
source /opt/geant4/bin/geant4.sh

export G4PARTICLEHPDATA="${G4PARTICLEHPDATA:-/opt/sag4n/data/JENDLTENDL01}"

if [[ "$#" -eq 0 ]]; then
    exec SaG4n --help
fi

# Preserve interactive/debug use cases.
if command -v "$1" >/dev/null 2>&1 || [[ "$1" == /* ]]; then
    exec "$@"
fi

exec SaG4n "$@"
EOF

WORKDIR /workspace

# Container behaves like the SaG4n executable: docker run ... <args> -> SaG4n <args>
ENTRYPOINT ["/usr/local/bin/sag4n-entrypoint"]
CMD ["--help"]
