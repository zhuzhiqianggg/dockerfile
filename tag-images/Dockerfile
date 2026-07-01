FROM nginx:1.30.3-alpine

LABEL maintainer="DevOps Team <devops@example.com>" \
      description="Tag-Image static image service"

COPY images/ /data/nginx/html/tag-image/
COPY nginx.conf /etc/nginx/nginx.conf

RUN chown -R nginx:nginx /data/nginx/html

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=1 \
    CMD wget -qO- http://127.0.0.1/health || exit 1

EXPOSE 80
