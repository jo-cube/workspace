# syntax=docker/dockerfile:1
# jvm.Dockerfile — code + Java/Kotlin/Gradle

ARG BASE_IMAGE=ghcr.io/jo-cube/workspace:code
FROM ${BASE_IMAGE}

USER dev

# SDKMAN at /opt/sdkman (not under /home/dev, so home volume can't shadow it).
# Owned by dev so 'sdk install' works at runtime.
ENV SDKMAN_DIR="/opt/sdkman"
RUN --mount=type=cache,target=/opt/sdkman/archives,sharing=locked,uid=1000,gid=1000 \
    curl -s "https://get.sdkman.io" | bash \
    && bash -lc 'source "$SDKMAN_DIR/bin/sdkman-init.sh" \
    && sdk install java 25.0.3-tem \
    && sdk install kotlin \
    && sdk install gradle' \
    && rm -rf "$SDKMAN_DIR/tmp"/* \
    && chown -R dev:dev $SDKMAN_DIR

ENV PATH="${SDKMAN_DIR}/candidates/java/current/bin:${SDKMAN_DIR}/candidates/kotlin/current/bin:${SDKMAN_DIR}/candidates/gradle/current/bin:${PATH}" \
    JAVA_HOME="${SDKMAN_DIR}/candidates/java/current" \
    GRADLE_USER_HOME=/cache/gradle

USER root
