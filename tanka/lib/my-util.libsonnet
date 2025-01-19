local k = import 'k.libsonnet';

{
  local container = k.core.v1.container,
  local pvc = k.core.v1.persistentVolumeClaim,
  local pv = k.core.v1.persistentVolume,
  local sc = k.storage.v1.storageClass,

  argocd_application(app): {
    apiVersion: 'argoproj.io/v1alpha1',
    kind: 'Application',
    metadata: {
      name: app.name,
      namespace: 'argocd',
    },
    spec: {
      destination: {
        namespace: if std.objectHas(app, 'namespace') then app.namespace else '%s-%s' % [app.type, app.name],
        server: 'https://kubernetes.default.svc',
      },
      project: 'default',
      source: {
        path: 'tanka',
        repoURL: 'https://github.com/raynix/argo-gitops.git',
        targetRevision: 'HEAD',
        plugin: {
          env: [
            { name: 'TK_ENV', value: app.type },
            { name: 'TK_TLA', value: 'name=%s' % [app.name] },
          ],
        },
      },
      syncPolicy: {
        automated: {
          prune: true,
        },
      },
    },
  },

  http_route(service, domain, gateway, gateway_ns='istio-system'): {
    apiVersion: 'gateway.networking.k8s.io/v1beta1',
    kind: 'HTTPRoute',
    metadata: {
      name: service,
    },
    spec: {
      parentRefs: [{
        kind: 'Gateway',
        name: gateway,
        namespace: gateway_ns,
      }],
      hostnames: [domain],
      rules: [{
        backendRefs: [{
          name: service,
          port: 8080,
        }],
      }],
    },
  },

  readiness_probe(port, initial_delay_seconds=5, period_seconds=5):
    container.readinessProbe.tcpSocket.withPort(port) +
    container.readinessProbe.withInitialDelaySeconds(initial_delay_seconds) +
    container.readinessProbe.withPeriodSeconds(period_seconds),

  liveness_probe(port, initial_delay_seconds=15, period_seconds=15):
    container.livenessProbe.tcpSocket.withPort(port) +
    container.livenessProbe.withInitialDelaySeconds(initial_delay_seconds) +
    container.livenessProbe.withPeriodSeconds(period_seconds),

  static_volume(name, namespace): {
    local sv = self,
    volume_size:: '1Gi',
    volume_ip:: '10.0.0.1',
    volume_path:: '/mnt/data',

    wordpress_volume:
      pv.new('wordpress-' + name) +
      pv.spec.withCapacity({ storage: sv.volume_size }) +
      pv.spec.withAccessModes('ReadWriteMany') +
      pv.spec.withPersistentVolumeReclaimPolicy('Retain') +
      pv.spec.claimRef.withNamespace(namespace) +
      pv.spec.claimRef.withName('wordpress') +
      pv.spec.withMountOptions(['hard', 'nfsvers=4.1']) +
      pv.spec.csi.withDriver('nfs.csi.k8s.io') +
      pv.spec.csi.withReadOnly(false) +
      pv.spec.csi.withVolumeHandle('wordpress-' + name + '-csi') +
      pv.spec.csi.withVolumeAttributes({ server: sv.volume_ip, share: sv.volume_path }),

    wordpress_volume_claim:
      pvc.new('wordpress') +
      pvc.metadata.withNamespace(namespace) +
      pvc.spec.withAccessModes('ReadWriteMany') +
      pvc.spec.resources.withRequests({ storage: sv.volume_size }),
  },

  dynamic_volume(name, namespace): {
    local dv = self,
    volume_size:: '1Gi',
    storage_class:: 'csi-nfs',

    wordpress_volume_claim:
      pvc.new('wordpress-' + name) +
      pvc.metadata.withNamespace(namespace) +
      pvc.spec.withAccessModes('ReadWriteMany') +
      pvc.spec.withStorageClassName(dv.storage_class) +
      pvc.spec.resources.withRequests({ storage: dv.volume_size }),
  },

  certificate(name, namespace, domains): {
    apiVersion: 'cert-manager.io/v1',
    kind: 'Certificate',
    metadata: {
      name: 'wordpress-' + name,
      namespace: namespace,
    },
    spec: {
      secretName: 'wordpress-' + name + '-cert',
      duration: '2160h0m0s',  // 90d
      renewBefore: '360h0m0s',  // 15d
      subject: {
        organizations: domains,
      },
      privateKey: {
        algorithm: 'RSA',
        size: 2048,
      },
      usages: ['server auth', 'client auth'],
      dnsNames: domains,
      issuerRef: {
        name: 'letsencrypt-issuer',
        kind: 'ClusterIssuer',
      },
    },
  },
}
