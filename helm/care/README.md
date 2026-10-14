# CARE Helm chart

Deploys the CARE backend (gunicorn API, Celery worker, Celery beat, migration Job), the care_fe frontend, and an nginx reverse proxy.

## Postgres, Redis and MinIO (optional, local/dev only)

`postgresql.enabled`, `redis.enabled` and `minio.enabled` are off by default and on in `values-k3d.yaml`. They deploy single-replica Postgres 17, Redis 8 and MinIO (`pgsty/silo`, the image `docker-compose.yaml` uses) inside the release. When they're on, the chart points the backend at them itself: it sets `POSTGRES_HOST`, `POSTGRES_PORT`, `DATABASE_URL`, `REDIS_URL`, `BUCKET_ENDPOINT` and `BUCKET_EXTERNAL_ENDPOINT`, overriding any value in the Secret.

The Secret still has to provide:
- `POSTGRES_USER`, `POSTGRES_PASSWORD` and `POSTGRES_DB`, which also initialise the database;
- `BUCKET_KEY` and `BUCKET_SECRET`, which become MinIO's login.

**Buckets.** A hook Job creates the buckets in `minio.buckets` after every install and upgrade. Buckets marked `public` get anonymous read-only access.

**Browser access to MinIO.** Browsers fetch and upload files with presigned URLs for `minio.host` (`minio.localhost` on k3d). That host has its own Ingress and an nginx proxy route that pass the `Host` header through unchanged, as MinIO's signature checks require.

**Data on a fixed folder (`persistence.hostPath`).** Each service can keep its data in a fixed node directory instead of a dynamically provisioned volume. On k3d, mount `~/care-data` into every node:

```bash
k3d cluster create care ... -v "$HOME/care-data:/mnt/care-data@server:*;agent:*"
```

The data then survives `helm uninstall` and `k3d cluster delete`. `docker-compose.shared-data.yaml` points the docker compose `db`, `redis` and `minio` services at the same folders, so you can switch between the two. **Run only one of them at a time**, because two servers on one data directory corrupt it.

**Migrations.** With in-chart Postgres, the migration Job runs **after** install, because the database doesn't exist before it. Upgrades still migrate first.

**Production.** Keep all three off, and use managed services through the Secret.

## nginx

`nginx.enabled` (on by default) deploys an nginx reverse proxy exposed as the `<fullname>-nginx` Service (for example, `care-nginx`). It routes requests by `Host`: `nginx.backendHost` goes to the API, and `nginx.frontendHost` goes to the frontend. Both hosts fall back to the `ingress.*Host` values. The API is the default server, so a request with an unknown host still reaches Django. To expose the proxy outside the cluster, set `nginx.service.type` to `NodePort` or `LoadBalancer`:

```bash
helm upgrade --install care helm/care -f helm/care/values-production.yaml \
  --set nginx.service.type=LoadBalancer
```

The Ingress still points directly at the api/frontend Services.

## Plugin frontends

Plugin frontends (`care_*_fe` repos) are Vite module-federation remotes. care_fe loads them in the browser from `<host>/assets/remoteEntry.js`. Each plugin runs as its own Deployment and Service (`<fullname>-fe-<name>`) and gets its **own host**. A sub-path won't work, because care_fe fetches plugin translations from `<origin>/locale/<lang>.json` and ignores the path.

1. **Build the image.** In CI, each plugin repo's `.github/workflows/image.yml` calls this repo's reusable `.github/workflows/build-plugin-fe.yml`. It pushes `ghcr.io/<plugin-repo>:sha-<short sha>` (plus branch, git-tag and `latest` tags) on pushes to the plugin's main branch and `v*` tags, and on PRs it only checks that the image builds. To build by hand, use the generic Dockerfile in this repo:
   ```bash
   docker build -f docker/plugin-fe/Dockerfile -t ghcr.io/care-ecosystem/care_radiology_fe:<tag> ../care_radiology_fe
   docker push ghcr.io/care-ecosystem/care_radiology_fe:<tag>
   ```
2. **Add it to the values file:**
   ```yaml
   frontendPlugins:
     - name: radiology
       host: radiology-fe.care.example.org
       image: { repository: ghcr.io/care-ecosystem/care_radiology_fe, tag: <tag> }
   ```
   Add the host to DNS and to `ingress.tls[].hosts`. The Ingress and the nginx proxy both route it.
3. **Register it in care_fe.** Either add it to `REACT_ENABLED_APPS` in `FE_PRODUCTION_ENV`, which requires a care_fe rebuild:
   ```
   REACT_ENABLED_APPS=care-ecosystem/care_radiology_fe@radiology-fe.care.example.org/assets/remoteEntry.js,...
   ```
   Or add a `plug_config` entry in the admin UI with `meta.url` set to the same `https://.../assets/remoteEntry.js`. This needs no rebuild.

### Testing a plugin frontend locally

- **Dev loop (no Docker).** In the plugin repo, run `npm run build && npx vite preview --port 4173`, or keep `npx vite build --watch` running alongside it. Then in `care_fe/.env.local` set
  `REACT_ENABLED_APPS=care-ecosystem/care_radiology_fe@localhost:4173/assets/remoteEntry.js`
  and run `npm run dev`. care_fe uses `http://` for `localhost` URLs. After rebuilding the plugin, reload the page: there is no hot reload across the remote.
- **Production image.** `docker run --rm -p 18080:8080 ghcr.io/care-ecosystem/care_radiology_fe:<tag>`, then point `REACT_ENABLED_APPS` at `localhost:18080/assets/remoteEntry.js`.
- **Whole chart.** In kind or minikube, install with your `frontendPlugins` list, then `kubectl port-forward svc/care-fe-radiology 18080:80` and use the same URL as above.

## One-time setup

1. **Secret values.** The chart renders the backend Secret from `backend.secretEnv`. `values.yaml` lists every key. Copy `secrets.example.yaml` to `secrets-<env>.yaml`, which is gitignored, fill it in, and pass it after the values file:
   ```bash
   helm upgrade --install care helm/care -f helm/care/values-k3d.yaml -f helm/care/secrets-k3d.yaml
   ```
   For production, store the contents of `secrets-production.yaml` as the `HELM_SECRETS_YAML` secret on the `production` GitHub environment. The deploy workflow passes it to Helm. Changing a value rolls the backend pods on the next upgrade. To manage the Secret outside the chart instead, set `backend.existingSecret`.
2. **Image pull access.** If the GHCR packages are private, create a pull secret and set `imagePullSecrets`.
3. **Values.** In `values-production.yaml`, replace the `example.org` hosts with your real domains.
4. **GitHub settings** (in both the `care` and `care_fe` repos):
   - Go to Settings → Environments → `production` and add **Required reviewers**.
   - Add the environment secret `KUBECONFIG_B64`, set to `base64 -w0 kubeconfig`. Use a kubeconfig scoped to the `care` namespace.
   - In care_fe only, add the repository variable `FE_PRODUCTION_ENV` with your `REACT_*` lines, for example `REACT_CARE_API_URL=https://careapi.example.org`.

## Release flow

When code is pushed to `production`, CI builds and pushes `ghcr.io/<repo>:production-<sha>-<run>`. The deploy job then waits for approval. Once a reviewer approves, CI runs `helm upgrade --atomic`. That command runs the migrations first, then rolls the pods. If the upgrade fails, Helm rolls back automatically.

Each repo changes only its own image tag and keeps the other component's currently deployed tag.

## Manual operations

```bash
# Deploy or roll back to a specific tag
#   Actions → "Deploy Care Production (Helm)" → Run workflow → image_tag
helm history care -n care
helm rollback care <REVISION> -n care   # note: rollback does not undo DB migrations
```
