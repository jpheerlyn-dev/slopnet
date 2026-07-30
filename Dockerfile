# The tag documents the Python line; the digest makes the build input immutable.
FROM python:3.12-slim-bookworm@sha256:d50fb7611f86d04a3b0471b46d7557818d88983fc3136726336b2a4c657aa30b

LABEL org.opencontainers.image.title="SlopNet" \
      org.opencontainers.image.description="A non-root, locked-down SlopNet gate runner" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/jpheerlyn-dev/slopnet"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Git is required by the checks and worktree runner. No language packages are
# installed into the image; SlopNet remains standard-library only.
RUN apt-get update \
    && apt-get install --no-install-recommends --yes git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && addgroup --gid 10001 slopnet \
    && adduser --disabled-password --gecos "" --uid 10001 --gid 10001 slopnet

WORKDIR /opt/slopnet
COPY --chown=10001:10001 . /opt/slopnet

USER 10001:10001
WORKDIR /workspace

ENTRYPOINT ["python3", "/opt/slopnet/slopnet"]
CMD ["check", "--all"]
