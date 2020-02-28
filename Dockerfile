FROM rhel8/go-toolset:1.13.4 AS builder
WORKDIR /opt/app-root/src/go/src/github.com/knative/client
USER root
COPY . .
RUN TAG="v0.13.0" make build

FROM ubi8:8-released
COPY --from=builder /opt/app-root/src/go/src/github.com/knative/client/kn /ko-app/kn

LABEL \
      com.redhat.component="openshift-serverless-1-tech-preview-client-kn-rhel8-container" \
      name="openshift-serverless-1-tech-preview/client-kn-rhel8" \
      version="0.13.0" \
      summary="Red Hat OpenShift Serverless 1 kn CLI" \
      description="CLI client 'kn' for managing Red Hat OpenShift Serverless 1" \
      io.k8s.display-name="Red Hat OpenShift Serverless 1 kn CLI" \
      io.k8s.description="CLI client 'kn' for managing Red Hat OpenShift Serverless 1" \
      io.openshift.build.source-location="https://github.com/openshift/knative-client" \
      maintainer="serverless-support@redhat.com"

ENTRYPOINT ["/ko-app/kn"]
