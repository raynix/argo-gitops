local ks = import 'github.com/jsonnet-libs/k8s-libsonnet/1.29/main.libsonnet';
local util = import 'ksonnet-util/util.libsonnet';

{
  _config:: {
    httpbin: {
      port: 80,
      name: 'httpbin',
      image: 'kennethreitz/httpbin:latest',
      host: 'httpbin.awes.one',
      cert: 'awes-one-cert',
    },
  },

  local namespace = ks.core.v1.namespace,
  local deployment = ks.apps.v1.deployment,
  local container = ks.core.v1.container,
  local port = ks.core.v1.containerPort,
  local gateway = ks.networking.v1beta1.gateway,
  local vs = ks.networking.v1beta1.virtualService,
  local c = $._config.httpbin,
  local mytools = (import 'mytools.libsonnet'),

  httpbin: {
    namespace: namespace.new(c.name),
    deployment: deployment.new(
                  c.name,
                  replicas=1,
                  containers=[
                    container.new(c.name, c.image)
                    + container.withPorts([{ containerPort: c.port, protocol: 'TCP', name: 'httpbin' }])
                    + util.resourcesRequests('100m', '100Mi')
                    + util.resourcesLimits('500m', '500Mi')
                    + container.livenessProbe.httpGet.withPath('/')
                    + container.livenessProbe.httpGet.withPort(c.port)
                    + container.readinessProbe.httpGet.withPath('/')
                    + container.readinessProbe.httpGet.withPort(c.port),
                  ],
                )
                + deployment.mixin.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.withNodeSelectorTerms(
                  {
                    matchExpressions: [{
                      key: 'kubernetes.io/arch',
                      operator: 'In',
                      values: [
                        'amd64',
                      ],
                    }],
                  }
                ),

    service: util.serviceFor(self.deployment),
  },
}
