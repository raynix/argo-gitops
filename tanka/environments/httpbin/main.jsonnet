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
      container.new(name, $._config.image) {
        ports: [
          { name: 'http', containerPort: $._config.port, protocol: 'TCP' },
        ],
        resources: {
          requests: {
            cpu: '100m',
            memory: '100Mi',
          },
          limits: {
            cpu: '500m',
            memory: '500Mi',
          },
        },
        livenessProbe: myutil.http_probe(path='/status/200'),
        readinessProbe: myutil.http_probe(path='/status/200'),
      },
    ],
  ),

  service: k.util.serviceFor(self.deployment),

  http_route: myutil.http_route($.service, $._config.host, 'kubernetes-gateway', port_name=name + '-http'),
}
