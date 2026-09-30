FROM golang:1.26.8-alpine AS gosu-builder

RUN apk add --no-cache git

WORKDIR /src/gosu

RUN git clone --depth 1 --branch 1.19 \
    https://github.com/tianon/gosu.git .

RUN CGO_ENABLED=0 go build -o /out/gosu .

FROM mariadb:11.4

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       --only-upgrade libssl3t64 openssl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=gosu-builder /out/gosu /usr/local/bin/gosu

RUN chmod 0755 /usr/local/bin/gosu \
    && gosu --version \
    && gosu mysql id
