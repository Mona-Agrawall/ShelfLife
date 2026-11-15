# Use slim Python 3.11 as base image
FROM python:3.11-slim

# Create a non-root user for security
RUN groupadd -r shelflife && useradd -r -g shelflife shelflife

# Set working directory
WORKDIR /app

# Install dependencies first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ ./app/

# Create data directory for SQLite persistence
RUN mkdir -p /data && chown shelflife:shelflife /data

# Switch to non-root user
USER shelflife

# Expose port
EXPOSE 5000

# Health check using /health endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

# Volume for SQLite database persistence
VOLUME ["/data"]

# Run with gunicorn (production WSGI server)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "60", "app.app:create_app()"]
