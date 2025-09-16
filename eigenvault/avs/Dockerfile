FROM golang:1.23.6-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git make bash

# Set working directory
WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN GOPRIVATE=github.com/Layr-Labs/* go mod download

# Copy source code
COPY cmd/ ./cmd/

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o performer ./cmd/main.go

# Final stage
FROM alpine:latest

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copy the binary from builder stage
COPY --from=builder /app/performer .

# Expose port
EXPOSE 8080

# Command to run
CMD ["./performer"]