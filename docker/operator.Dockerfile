# EigenVault Operator Dockerfile
FROM rust:1.70-slim as builder

# Install system dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Cargo files
COPY eigenvault/operator/Cargo.toml ./
COPY eigenvault/operator/Cargo.lock ./

# Copy source code
COPY eigenvault/operator/src ./src/

# Build the application
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN useradd -r -s /bin/false eigenvault

# Set working directory
WORKDIR /app

# Copy binary from builder stage
COPY --from=builder /app/target/release/eigenvault-operator /usr/local/bin/

# Copy configuration templates
COPY eigenvault/operator/config.example.yaml /app/config.yaml
COPY circuits/ /app/circuits/

# Create directories
RUN mkdir -p /app/keys /app/logs /app/data && \
    chown -R eigenvault:eigenvault /app

# Switch to app user
USER eigenvault

# Expose port
EXPOSE 9000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:9000/health || exit 1

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/eigenvault-operator"]
CMD ["start", "--config", "/app/config.yaml"]