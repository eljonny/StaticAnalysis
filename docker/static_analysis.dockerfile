FROM debian:stable-slim AS base

ENV CLANG_VERSION=19
ENV CPPCHECK_VERSION=2.17.1
ENV INFER_VERSION=1.2.0
ENV CXX=clang++
ENV CC=clang
ENV DEBIAN_FRONTEND=noninteractive

ENV INFER_EP=https://github.com/facebook/infer/releases/download/v$INFER_VERSION/infer-linux-x86_64-v$INFER_VERSION.tar.xz

# Install dependencies
RUN apt-get update && apt-get full-upgrade -y
RUN apt-get install -y apt-utils
RUN apt-get install -y build-essential python3 \
      python3-pip git wget libssl-dev ninja-build \
      gnupg lsb-release software-properties-common \
      flawfinder curl cmake

RUN curl -sSL $INFER_EP | tar -C /opt -xJ
RUN ln -s /opt/infer-linux-x86_64-v$INFER_VERSION/bin/infer /usr/local/bin/infer

# Copy the llvm.sh installation script
COPY --chmod=500 llvm.sh /opt/llvm/llvm.sh

# Execute the LLVM install script with the version number
WORKDIR /opt/llvm
RUN ./llvm.sh $CLANG_VERSION

# Clean up
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip3 install --break-system-packages PyGithub pylint

# Create symlinks for clang and clang++
RUN ln -s "$(which clang++-$CLANG_VERSION)" /usr/bin/clang++
RUN ln -s "$(which clang-$CLANG_VERSION)" /usr/bin/clang

# Create a symlink for python
RUN ln -s /usr/bin/python3 /usr/bin/python

# Install cppcheck
WORKDIR /opt
RUN git clone https://github.com/danmar/cppcheck.git
WORKDIR /opt/cppcheck
RUN git checkout tags/$CPPCHECK_VERSION
WORKDIR /opt/cppcheck/build
RUN cmake -G Ninja .. && ninja all && ninja install
