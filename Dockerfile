# ----------------------------
# Stage 1: Build
# ----------------------------
FROM python:3.9-slim as builder

ENV PYTHONUNBUFFERED=1

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --upgrade pip && pip install --no-cache-dir -r requirements.txt

# Copy application source code
COPY . .

# ----------------------------
# Stage 2: Production Image
# ----------------------------
FROM python:3.9-slim

ENV PYTHONUNBUFFERED=1

# Install runtime packages: nginx for TLS termination, supervisor to run both services
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    supervisor \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the built application from the builder stage
COPY --from=builder /app /app

# Create a non-root user and change ownership
RUN adduser --disabled-password --gecos "" appuser && chown -R appuser:appuser /app
USER appuser

# Copy production configuration files for Nginx and Supervisor.
# (Make sure these files exist in your repo under the "deploy" folder)
COPY --chown=appuser:appuser deploy/nginx.conf /etc/nginx/nginx.conf
COPY --chown=appuser:appuser deploy/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy SSL certificates into the image (or mount them at runtime).
# These should include your certificate (fullchain.pem) and private key (privkey.pem)
COPY --chown=appuser:appuser deploy/ssl /etc/ssl/private

# Expose standard HTTP and HTTPS ports
EXPOSE 80 443

# Start Supervisor to run Nginx and Gunicorn
CMD ["/usr/bin/supervisord", "-n"]
