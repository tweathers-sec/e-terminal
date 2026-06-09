FROM golang:1.26-alpine AS build
WORKDIR /src
RUN apk add --no-cache git
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN set -eu; mkdir -p /out; \
    for t in darwin/arm64 darwin/amd64 linux/amd64 linux/arm64; do \
      os="${t%/*}"; arch="${t#*/}"; \
      for spec in ".:e-session-view" "./rec:e-session-rec"; do \
        pkg="${spec%:*}"; name="${spec#*:}"; \
        CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" \
          go build -trimpath -buildvcs=false -ldflags "-s -w" -o "/out/${name}-${os}-${arch}" "$pkg"; \
      done; \
    done

FROM scratch AS export
COPY --from=build /out/ /
