# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.205.2/containers/debian/.devcontainer/base.Dockerfile

# [Choice] Debian version (use bullseye or stretch on local arm64/Apple Silicon): bullseye, buster, stretch
ARG VARIANT="bullseye"
FROM mcr.microsoft.com/vscode/devcontainers/base:0-${VARIANT}

# ** [Optional] Uncomment this section to install additional packages. **
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    csvtool \
    imagemagick \
    librsvg2-bin \
    fonts-liberation2 \
    fonts-roboto
# Fix issue with ghostscript permission
RUN sed -i '/disable ghostscript format types/,+6d' /etc/ImageMagick-6/policy.xml
