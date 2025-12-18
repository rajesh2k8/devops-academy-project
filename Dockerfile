# Simple Nginx-based image
FROM nginx:stable

# Optional: serve a custom landing page
COPY ./index.html /usr/share/nginx/html/index.html
COPY ./nginx.conf /etc/nginx/conf.d/default.conf

# Expose app port (informational)
EXPOSE 8080
