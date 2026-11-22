# Oracle image: builds the original GrappleMap tools (reference/GrappleMap, read-only submodule)
# out of tree, with the original SConstruct and flags. See README.md.
# Ubuntu 18.04 (amd64 manifest): Boost 1.65 still ships the legacy GIL png_io the original uses.
FROM ubuntu:18.04@sha256:dca176c9663a7ba4c1f0e710986f5a25e672842963d95b960191e2d9f7185ebe AS original

ENV LC_ALL=C DEBIAN_FRONTEND=noninteractive

# Exact versions: bionic's archive is frozen, so digest + versions fix compiler and libm.
# No apt-get upgrade. libc6 is pinned together with libc6-dev.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    libc6=2.27-3ubuntu1.6 \
    libc6-dev=2.27-3ubuntu1.6 \
    gcc-7=7.5.0-3ubuntu1~18.04 \
    g++-7=7.5.0-3ubuntu1~18.04 \
    libstdc++-7-dev=7.5.0-3ubuntu1~18.04 \
    g++=4:7.4.0-1ubuntu2.3 \
    scons=3.0.1-1 \
    pkg-config=0.29.1-0ubuntu2 \
    libboost-program-options-dev=1.65.1.0ubuntu1 \
    libboost-filesystem-dev=1.65.1.0ubuntu1 \
    libboost-system-dev=1.65.1.0ubuntu1 \
    libosmesa6-dev=20.0.8-0ubuntu1~18.04.1 \
    libglu1-mesa-dev=9.0.0-2.1build1 \
    libftgl-dev=2.1.3~rc5-4+nmu1.2 \
    libfreetype6-dev=2.8.1-2ubuntu2.2 \
    libpng-dev=1.6.34-1ubuntu0.18.04.2 \
    libgraphviz-dev=2.40.1-2 \
 && apt-get clean \
 && find /var/lib/apt/lists -type f -delete

# Guard: the compiler must target generic x86-64 (no -march=native / FMA).
RUN test "$(gcc -Q --help=target | awk '$1 == "-march=" {print $2}')" = "x86-64"

# Out-of-tree copy keeps the layout SConstruct expects (../GrappleMap.txt); the submodule is never modified.
COPY reference/GrappleMap/src /oracle/src
COPY reference/GrappleMap/GrappleMap.txt /oracle/GrappleMap.txt

RUN scons -C /oracle/src -j"$(nproc)" \
      grapplemap-indexer grapplemap-dbtojs grapplemap-mkpospages \
 && cd /oracle/src \
 && install -m 0755 grapplemap-indexer grapplemap-dbtojs grapplemap-mkpospages /usr/local/bin/ \
 && test -f images.o && test -f rendering.o && test -f playerdrawer.o

RUN { gcc --version | head -n1; \
      dpkg-query -W -f='${Package} ${Version}\n' libc6 libboost-program-options-dev libboost-filesystem-dev libboost-system-dev libosmesa6 libftgl2 libgraphviz-dev libpng-dev | sort; \
    } > /oracle/VERSIONS

# Dumper (#34): own code linked against the original's `common` objects (SConstruct:33) and cmdlibs.
# -ffp-contract=off: no FMA contraction in the dumper's own arithmetic (the generic x86-64 target has no FMA anyway).
FROM original AS dumper
COPY tools/oracle/dump /oracle/dump
RUN cd /oracle/src \
 && g++ -std=c++1y -O3 -DNDEBUG -ffp-contract=off -Wall -Wextra -pedantic -Wno-missing-field-initializers -Werror \
      -I/oracle/src -o /usr/local/bin/grapplemap-dump /oracle/dump/dump.cpp \
      graph.o graph_util.o positions.o viables.o persistence.o paths.o playback.o icosphere.o editor.o metadata.o \
      md5.o js_conversions.o -lboost_program_options \
 && install -m 0755 /oracle/dump/run.sh /usr/local/bin/grapplemap-oracle-dump

# Reference images (#35): own code linked like grapplemap-mkpospages (SConstruct:35-50: images, rendering, common
# and its LIBS), same original flags (-DUSE_FTGL: Style's layout depends on it) plus -ffp-contract=off -Werror.
COPY tools/oracle/images /oracle/images
RUN cd /oracle/src \
 && g++ -std=c++1y -O3 -DNDEBUG -DUSE_FTGL -ffp-contract=off -Wall -Wextra -pedantic -Wno-missing-field-initializers -Werror \
      $(pkg-config --cflags libgvc freetype2) -I/oracle/src -o /usr/local/bin/grapplemap-images /oracle/images/images.cpp \
      images.o rendering.o playerdrawer.o \
      graph.o graph_util.o positions.o viables.o persistence.o paths.o playback.o icosphere.o editor.o metadata.o \
      md5.o js_conversions.o \
      -lOSMesa -lGLU -lftgl -lboost_program_options -lpng -lboost_filesystem -lboost_system -lpthread -lgvc -lcgraph
