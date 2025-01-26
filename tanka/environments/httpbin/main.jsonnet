local k = import 'ksonnet-util/kausal.libsonnet';
local myutil = import 'my-util.libsonnet';

function(name='httpbin') {
  _config:: {
    port: 80,
    image: 'kennethreitz/httpbin:latest',
    host: 'httpbin.awes.one',
  },

  local namespace = k.core.v1.namespace,
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local port = k.core.v1.containerPort,

  namespace: namespace.new(name) {
    metadata+: {
      labels: {
        'istio-injection': 'enabled',
      },
    },
  },

  deployment: deployment.new(
    name=name,
    replicas=1,
    containers=[
      container.new(name, $._config.image)
      + container.withPorts([port.new(name, $._config.port)])
      + k.util.resourcesRequests('100m', '100Mi')
      + k.util.resourcesLimits('500m', '500Mi')
      + container.livenessProbe.httpGet.withPath('/')
      + container.livenessProbe.httpGet.withPort($._config.port)
      + container.readinessProbe.httpGet.withPath('/')
      + container.readinessProbe.httpGet.withPort($._config.port),
    ],
  ),

  service: k.util.serviceFor(self.deployment),

  http_route: myutil.http_route($.service, $._config.host, 'kubernetes-gateway'),
}
