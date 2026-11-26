# Golden image: renders our images in a pinned Mesa (softpipe), with the pinned Odin. See README.md.
# The repo (with the reference/GrappleMap submodule) is mounted at run time, never copied.
# Ubuntu 24.04, amd64 manifest pinned by digest.
FROM ubuntu:24.04@sha256:9a04f13b3f80ef056361e30868593b1cfd2279fe19e4081cb93a90bf56819d6a

ENV LC_ALL=C DEBIAN_FRONTEND=noninteractive

# Ubuntu's snapshot service freezes the archive at SNAPSHOT, so the exact versions below stay installable. It is
# served over https: ca-certificates comes first from the image's own archive (TLS trust only; apt still checks the
# archive signatures). Every package that touches the pixels or the build is pinned to an exact version.
ARG SNAPSHOT=20261120T000000Z
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -f /etc/apt/sources.list.d/ubuntu.sources \
 && for suite in noble noble-updates noble-security; do \
      echo "deb https://snapshot.ubuntu.com/ubuntu/${SNAPSHOT} ${suite} main universe"; \
    done > /etc/apt/sources.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
    libgl1-mesa-dri=25.2.8-0ubuntu0.24.04.5 \
    libglx-mesa0=25.2.8-0ubuntu0.24.04.5 \
    mesa-libgallium=25.2.8-0ubuntu0.24.04.5 \
    libgl1-mesa-dev=25.2.8-0ubuntu0.24.04.5 \
    xvfb=2:21.1.12-1ubuntu1.9 \
    xauth=1:1.1.2-1build1 \
    clang-18=1:18.1.3-1ubuntu1 \
    clang=1:18.0-59~exp2 \
    libc6-dev=2.39-0ubuntu8.12 \
    libx11-dev=2:1.8.7-1ubuntu0.1 \
    libxrandr-dev=2:1.5.2-2build1 \
    libxinerama-dev=2:1.1.4-3build1 \
    libxcursor-dev=1:1.2.1-1build1 \
    libxi-dev=2:1.8.1-1build1 \
    curl=8.5.0-2ubuntu10.16 \
 && apt-get clean \
 && find /var/lib/apt/lists -type f -delete

# The pinned Odin (.odin-version), the release archive CI installs (laytan/setup-odin, `release:`), checked by sha256.
ARG ODIN_RELEASE=dev-2026-11a
ARG ODIN_SHA256=65c9f6e97d6f8a30930e151f270ce5aeaa98fe8b2ba49fe067394e2af04f7618
RUN curl -fsSL -o /tmp/odin.tar.gz \
      "https://github.com/odin-lang/Odin/releases/download/${ODIN_RELEASE}/odin-linux-amd64-${ODIN_RELEASE}.tar.gz" \
 && echo "${ODIN_SHA256}  /tmp/odin.tar.gz" | sha256sum -c - \
 && mkdir -p /opt/odin \
 && tar -xzf /tmp/odin.tar.gz -C /opt/odin --strip-components=1 \
 && rm /tmp/odin.tar.gz \
 && ln -s /opt/odin/odin /usr/local/bin/odin \
 && echo "${ODIN_RELEASE}" > /opt/odin/RELEASE

# Software GL, softpipe (as the oracle, tools/oracle/README.md "Driver"): llvmpipe's bytes depend on threads and
# the host's SIMD width.
ENV LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=softpipe HOME=/tmp

RUN { odin version; clang --version | head -n1; \
      dpkg-query -W -f='${Package} ${Version}\n' libgl1-mesa-dri mesa-libgallium xvfb | sort; \
    } > /opt/VERSIONS

WORKDIR /repo
