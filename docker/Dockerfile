FROM ubuntu:latest

SHELL ["/bin/bash", "-c"]

# 1. Install prerequisites (Ubuntu 24.04 includes OpenJDK 21 in default repos)
RUN apt-get update && apt-get install -y \
    curl \
    tar \
    zip \
    jq \
    git \
    gh \
    unzip \
    openjdk-21-jdk \
    maven \
    && rm -rf /var/lib/apt/lists/*

# 2. Verify installation
RUN java -version && mvn --version

RUN mkdir -p /root/.m2
ADD settings.xml /root/.m2/

CMD ["/bin/bash"]