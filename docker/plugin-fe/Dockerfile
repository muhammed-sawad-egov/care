# syntax=docker/dockerfile:1.7
# Generic image for a CARE plugin frontend (Vite module-federation remote).
# Build it against a plugin repo checkout, e.g.:
#   docker build -f docker/plugin-fe/Dockerfile -t care_radiology_fe:local ../care_radiology_fe
# The result serves dist/ (remoteEntry.js, chunks, locale/) on :8080 with CORS enabled,
# so care_fe can load it cross-origin.

FROM node:22-bookworm-slim AS build
WORKDIR /app
ENV NODE_OPTIONS="--max-old-space-size=4096"
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build && test -f dist/assets/remoteEntry.js

FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY <<'EOF' /etc/nginx/conf.d/default.conf
server {
  listen 8080;
  root /usr/share/nginx/html;

  include mime.types;
  types {
    text/javascript js mjs;
  }

  # care_fe runs on another origin and loads remoteEntry.js, chunks and locale/*.json from here.
  add_header Access-Control-Allow-Origin "*" always;
  add_header X-Content-Type-Options "nosniff" always;

  location = /healthz {
    access_log off;
    return 200 "ok\n";
  }

  # remoteEntry.js and several chunk names are not content-hashed, so always revalidate
  # (cheap via ETag) instead of caching; otherwise browsers keep running old plugin code.
  location / {
    add_header Access-Control-Allow-Origin "*" always;
    add_header Cache-Control "no-cache" always;
    try_files $uri =404;
  }
}
EOF
EXPOSE 8080
