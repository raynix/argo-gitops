local k = import 'k.libsonnet';

{
  local this = self,
  local container = k.core.v1.container,
  local pvc = k.core.v1.persistentVolumeClaim,
  local pv = k.core.v1.persistentVolume,
  local sc = k.storage.v1.storageClass,

  traverse(obj, keys, default=''):
    if std.objectHas(obj, keys[0]) then
      if std.length(keys) == 1 then
        obj[keys[0]]
      else
        this.traverse(obj[keys[0]], keys[1:], default=default)
    else
      default,

  argocd_application(app): {
    apiVersion: 'argoproj.io/v1alpha1',
    kind: 'Application',
    metadata: {
      name: '%s-%s' % [app.type, app.name],
      namespace: 'argocd',
    },
    spec: {
      destination: {
        namespace: if std.objectHas(app, 'namespace') then app.namespace else '%s-%s' % [app.type, app.name],
        server: 'https://kubernetes.default.svc',
      },
      project: 'default',
      source: {
        path: this.traverse(app, ['path'], 'tanka'),
        repoURL: this.traverse(app, ['repoURL'], 'https://github.com/raynix/argo-gitops.git'),
        targetRevision: 'HEAD',
        [if !std.objectHas(app, 'path') then 'plugin']: {
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
        syncOptions: [
          'CreateNamespace=true',
          'RespectIgnoreDifferences=true',
        ],
      },
    },
  },

  gateway(domains, sites): {
    local site_domain(domains, site) =
      [domain for domain in domains if std.endsWith(site.domain, domain)][0],
    apiVersion: 'gateway.networking.k8s.io/v1beta1',
    kind: 'Gateway',
    metadata: {
      annotations: {
        'networking.istio.io/service-type': 'NodePort',
      },
      name: 'kubernetes-gateway',
    },
    spec: {
      gatewayClassName: 'istio',
      listeners: [
        {
          name: site.name + '-https',
          port: 443,
          protocol: 'HTTPS',
          hostname: site.domain,
          allowedRoutes: {
            kinds: [
              {
                kind: 'HTTPRoute',
              },
            ],
            namespaces: { from: 'All' },
          },
          tls: {
            certificateRefs: [
              {
                kind: 'Secret',
                group: '',
                name: std.strReplace(site_domain(domains, site), '.', '-') + '-cert',
              },
            ],
          },
        }
        for site in sites
        if std.objectHas(site, 'domain')
      ],
    },
  },

  http_route(service, domain, gateway, gateway_ns='istio-system', port_name='http'): {
    apiVersion: 'gateway.networking.k8s.io/v1beta1',
    kind: 'HTTPRoute',
    metadata: {
      name: service.metadata.name,
    },
    spec: {
      parentRefs: [{
        kind: 'Gateway',
        name: gateway,
        namespace: gateway_ns,
      }],
      hostnames: [domain],
      rules: [{
        backendRefs: [
          {
            name: port.name,
            port: port.port,
          }
          for port in service.spec.ports
          if port.name == port_name
        ],
      }],
    },
  },

  http_probe(port, path='/', initial_delay_seconds=15, period_seconds=15): {
    initialDelaySeconds: initial_delay_seconds,
    periodSeconds: period_seconds,
    httpGet: {
      path: path,
      port: port,
      scheme: 'HTTP',
    },
  },

  tcp_probe(port, initial_delay_seconds=15, period_seconds=15): {
    initialDelaySeconds: initial_delay_seconds,
    periodSeconds: period_seconds,
    tcpSocket: {
      port: port,
    },
  },

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

    pvc:
      pvc.new('wordpress') +
      pvc.metadata.withNamespace(namespace) +
      pvc.spec.withAccessModes('ReadWriteMany') +
      pvc.spec.resources.withRequests({ storage: sv.volume_size }),
  },

  dynamic_volume(name, namespace): {
    local dv = self,
    volume_size:: '1Gi',
    storage_class:: 'nfs-csi',

    pvc:
      pvc.new('pvc-' + name) +
      pvc.metadata.withNamespace(namespace) +
      pvc.spec.withAccessModes('ReadWriteMany') +
      pvc.spec.withStorageClassName(dv.storage_class) +
      pvc.spec.resources.withRequests({ storage: dv.volume_size }),
  },

  certificate(domain, sites): {
    apiVersion: 'cert-manager.io/v1',
    kind: 'Certificate',
    metadata: {
      name: domain,
    },
    spec: {
      secretName: std.strReplace(domain, '.', '-') + '-cert',
      duration: '2160h0m0s',  // 90d
      renewBefore: '360h0m0s',  // 15d
      subject: {
        organizations: [domain],
      },
      privateKey: {
        algorithm: 'RSA',
        size: 2048,
      },
      usages: ['server auth', 'client auth'],
      dnsNames: [site.domain for site in sites if std.objectHas(site, 'domain') && std.endsWith(site.domain, domain)],
      issuerRef: {
        name: 'letsencrypt-issuer',
        kind: 'ClusterIssuer',
      },
    },
  },
}
