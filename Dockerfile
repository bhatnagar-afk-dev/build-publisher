# Use a small base image
FROM nginx:alpine

# Copy a test HTML file
COPY ./public /usr/share/nginx/html

# Expose port (optional for CI)
EXPOSE 80

# NGINX will automatically start as the container's entrypoint