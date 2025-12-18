# Simple Nginx-based image
FROM nginx:stable

# Optional: serve a custom landing page
COPY ./index.html /usr/share/nginx/html/index.html

# Expose default port (informational)
EXPOSE 80
