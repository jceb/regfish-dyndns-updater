# Documentation: https://just.systems/man/en/

set shell := ["bash", "-euo", "pipefail", "-c"]

# To override the value of REGISTRY, run: just --set REGISTRY
# jceb/regfish-dyndns-updater push

REGISTRY := "jceb/regfish-dyndns-updater"

# Print this help
help:
    @just -l

# Format Justfile
format:
    @just --fmt --unstable

# Build image
build:
    @nix-build

_load:
    @eval "$(just build)" | gzip --fast

# Load image into docker
load:
    @just _load | docker load

# Push image into registry
push:
    just _load | skopeo copy docker-archive:/dev/stdin "docker://$(just repository)"; \
    just _load | skopeo copy docker-archive:/dev/stdin "docker://{{ REGISTRY }}:latest";

# Run image shell
inspect:
    @just _load | skopeo inspect docker-archive:/dev/stdin

# Run image shell
docker-shell: load
    @TAG="$(just nixtag)"; \
    docker run -it --rm "$(just repository)" sh

# Compute image tag
tag:
    @SHA="$(git rev-parse --short HEAD)"; \
     DIRTY="$(test -z "$(git status --porcelain)" || echo "-dirty")"; \
     echo "${SHA}${DIRTY}"

# Compute nix image tag
nixtag:
    @just build | xargs awk '/^exec/ {print $3}' | xargs basename | sed -ne 's/-.*//p'

# Compute image digest
digest:
    @just _load | skopeo inspect docker-archive:/dev/stdin | yq e '.Digest'

# Compute image repository including tag
repository:
    @TAG="$(just nixtag)"; \
    echo "{{ REGISTRY }}:$TAG"

# Compute image repository including tag
repository-digest:
    @TAG="$(just nixtag)"; \
    echo "{{ REGISTRY }}:$TAG@$(just digest)"
