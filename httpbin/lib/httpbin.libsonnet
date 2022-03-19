(import "ksonnet-util/kausal.libsonnet") +
{
  _config:: {
    httpbin: {
      port: 80,
      name: "httpbin",
      image: "kennethreitz/httpbin:latest",
      host: "httpbin.awes.one",
      cert: "awes-one-cert",
    }
  },

  local namespace = $.core.v1.namespace,
  local deployment = $.apps.v1.deployment,
  local container = $.core.v1.container,
  local port = $.core.v1.containerPort,
  local gateway = $.networking.v1beta1.gateway,
  local vs = $.networking.v1beta1.virtualService,
  local c = $._config.httpbin,
  local mytools = (import "mytools.libsonnet"),

  httpbin: {
    namespace: namespace.new(c.name)
    + namespace.mixin.metadata.withLabels({ "istio.io/rev": "magpie"}),
    deployment: deployment.new(
      name=c.name,
      replicas=1,
      containers=[
        container.new(c.name, c.image)
        + container.withPorts([port.new(c.name, c.port)])
        + $.util.resourcesRequests("100m", "100Mi")
        + $.util.resourcesLimits("500m", "500Mi")
        + container.livenessProbe.httpGet.withPath("/")
        + container.livenessProbe.httpGet.withPort(c.port)
        + container.readinessProbe.httpGet.withPath("/")
        + container.readinessProbe.httpGet.withPort(c.port),
      ],
    )
    + deployment.mixin.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.withNodeSelectorTerms(
      {
        matchExpressions: [{
          key: "kubernetes.io/arch",
          operator: "In",
          values: [
            "amd64",
          ]
        }]
      }),

    service: $.util.serviceFor(self.deployment),
    gateway: mytools.gatewayFor(c.name, c.cert, [c.host]),
    vs: mytools.virtualServiceFor(c.name, c.name, [c.host]),
  },
}
