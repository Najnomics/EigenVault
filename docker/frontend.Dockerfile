# EigenVault Frontend Dockerfile
FROM node:18-alpine as builder

# Set working directory
WORKDIR /app

# Copy package files
COPY frontend/package.json frontend/yarn.lock ./

# Install dependencies
RUN yarn install --frozen-lockfile

# Copy source code
COPY frontend/ ./

# Build the application
RUN yarn build

# Runtime stage
FROM nginx:alpine

# Copy build artifacts
COPY --from=builder /app/build /usr/share/nginx/html

# Copy nginx configuration
COPY docker/nginx.conf /etc/nginx/nginx.conf

# Create nginx user
RUN addgroup -g 1001 -S nginx && \
    adduser -S -D -H -u 1001 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost/ || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]