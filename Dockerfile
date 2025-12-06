FROM python:3.11-slim

# Install git for repo operations
RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the inventory script
COPY inventory.py .
RUN chmod +x inventory.py

# Create workspace directory
RUN mkdir -p /workspace

# Set default environment variables
ENV OUTPUT_DIR=/workspace/docs
ENV PYTHONUNBUFFERED=1

# Run the script
CMD ["/app/inventory.py"]
