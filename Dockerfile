FROM golang:1-alpine AS builder

ARG MIHOMO_TAG
ARG MIHOMO_COMMIT

RUN apk add --no-cache upx git

RUN --mount=type=cache,id=go-build,target=/root/.cache/go-build \
    --mount=type=cache,id=go-mod,target=/go/pkg/mod \
    go install mvdan.cc/garble@latest

WORKDIR /src
COPY mihomo/go.mod mihomo/go.sum ./
RUN --mount=type=cache,id=go-mod,target=/go/pkg/mod \
    go mod download
COPY mihomo/ .

RUN mkdir -p /mihomo-config && cd /mihomo-config && \
    wget -q https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb && \
    wget -q https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat && \
    wget -q https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat

RUN --mount=type=cache,id=go-build,target=/root/.cache/go-build \
    --mount=type=cache,id=go-mod,target=/go/pkg/mod \
    SEED=$(echo -n "${MIHOMO_COMMIT}" | xxd -r -p | head -c 8 | base64) && \
    CGO_ENABLED=0 garble -literals -seed="${SEED}" build \
        -v -trimpath \
        -ldflags "-X 'github.com/metacubex/mihomo/constant.Version=${MIHOMO_TAG}' -X 'github.com/metacubex/mihomo/constant.BuildTime=$(date -u)' -w -s -buildid=" \
        -o /src/bin/iperf3 . && \
    upx /src/bin/iperf3 && \
    /src/bin/iperf3 -v | grep -F "${MIHOMO_TAG}"

FROM alpine:latest AS runner
RUN apk add --no-cache tini ca-certificates tzdata iptables
COPY --from=builder /mihomo-config/ /root/.config/mihomo/
COPY --from=builder /src/bin/iperf3 /usr/local/bin/iperf3
VOLUME ["/root/.config/mihomo/"]
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["iperf3"]
