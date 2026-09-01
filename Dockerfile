# Milvus standalone, packaged for Railway as a single service.
#
# Upstream ships Milvus as a distributed system whose "standalone" mode still
# expects an external etcd and an S3-compatible object store. Milvus can run
# all three roles in one process (this is what upstream's own
# standalone_embed.sh does), which is what makes a one-service Railway
# deployment possible:
#
#   DEPLOY_MODE=STANDALONE   embedded etcd refuses to start in distributed mode
#   ETCD_USE_EMBED=true      run etcd inside the Milvus process
#   COMMON_STORAGETYPE=local write segments to the local volume, not to S3
#
# The embedded etcd needs a config file that the upstream image does not ship,
# so it is baked in here rather than published as a template variable.
FROM milvusdb/milvus:v2.6.22@sha256:a8ac051e59eb084d41bd317ec51aac28553d664e91c43a806ccd6a1538abc1df

COPY embedEtcd.yaml /milvus/configs/embedEtcd.yaml
COPY user.yaml /milvus/configs/user.yaml
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh

RUN chmod 0644 /milvus/configs/embedEtcd.yaml /milvus/configs/user.yaml \
 && chmod 0755 /usr/local/bin/railway-entrypoint.sh

ENV DEPLOY_MODE=STANDALONE \
    ETCD_USE_EMBED=true \
    ETCD_DATA_DIR=/var/lib/milvus/etcd \
    ETCD_CONFIG_PATH=/milvus/configs/embedEtcd.yaml \
    COMMON_STORAGETYPE=local \
    COMMON_SECURITY_AUTHORIZATIONENABLED=true \
    MILVUS_DATA_DIR=/var/lib/milvus

EXPOSE 19530 9091

ENTRYPOINT ["/tini", "--", "/usr/local/bin/railway-entrypoint.sh"]
