# milvus-railway

Wrapper image for deploying [Milvus](https://github.com/milvus-io/milvus) on
[Railway](https://railway.com) as a **single service**.

Upstream's standalone mode still expects an external etcd and an S3-compatible
object store, which is why every Milvus template on Railway bills three or four
containers. Milvus can instead run etcd inside its own process and keep segments
on a local volume — the same thing upstream's `standalone_embed.sh` does — so one
container and one volume is enough:

| variable | value | why |
| --- | --- | --- |
| `DEPLOY_MODE` | `STANDALONE` | embedded etcd panics under distributed mode |
| `ETCD_USE_EMBED` | `true` | run etcd in-process |
| `ETCD_CONFIG_PATH` | `/milvus/configs/embedEtcd.yaml` | file the upstream image does not ship; baked in here |
| `COMMON_STORAGETYPE` | `local` | segments on the volume instead of S3 |

All four are baked into the image, so they never appear on the Railway deploy
form.

## Variables

| variable | default | notes |
| --- | --- | --- |
| `MILVUS_ROOT_PASSWORD` | — | required; the container refuses to boot without it |

Milvus reads `COMMON_SECURITY_DEFAULTROOTPASSWORD` only when it initialises an
empty metastore, and it has no offline password reset. The entrypoint therefore
records the applied password on the volume and, on any later boot where
`MILVUS_ROOT_PASSWORD` differs, calls Milvus's own `update_password` API — so
changing the variable and redeploying is a working password reset.

## Ports

* `19530` — gRPC **and** the RESTful v2 API (Milvus multiplexes both on this port)
* `9091` — `/healthz`

Milvus does not read `$PORT`; the Railway service publishes an HTTP domain and a
TCP proxy both targeting 19530.
