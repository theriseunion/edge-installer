# Build stage
FROM golang:1.23-alpine AS builder

WORKDIR /workspace

# Copy go mod files
COPY go.mod go.mod
COPY go.sum go.sum

# Cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download

# Copy the go source
COPY cmd/ cmd/
COPY api/ api/
COPY pkg/ pkg/

# Build
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o installer cmd/installer/main.go

# Runtime stage
FROM alpine:3.19

WORKDIR /

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates

# Copy the installer binary
COPY --from=builder /workspace/installer .

# Copy Helm charts (these should be mounted or included in the image)
# COPY charts/ /charts/

USER 65532:65532

ENTRYPOINT ["/installer"]
