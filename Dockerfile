FROM ruby:3.4-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock* ./
RUN bundle install --without development test

FROM ruby:3.4-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY . .

ENV MALLOC_ARENA_MAX=2
ENV RUBY_YJIT_ENABLE=1

EXPOSE 5555

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:5555/v1/health || exit 1

CMD ["bundle", "exec", "iodine", "--yjit", "--yjit-exec-mem-size=8", "-p", "5555"]
