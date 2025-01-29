local tk = import 'tanka-util/main.libsonnet';
local domains = std.parseYaml(importstr '../domains.yaml');
local util = import 'my-util.libsonnet';
local manifests = std.parseYaml(importstr '../apps.yaml');
local sites = [
  i { type: k }
  for k in std.objectFields(manifests)
  for i in manifests[k]
  if std.objectHas(i, 'domain')
];

function(name='') {
  data:: {
    ['certificate-' + domain]: util.certificate(domain, sites)
    for domain in domains
  } + {
    gateway: util.gateway(domains, sites),
    istio: import 'istio.json',
  },

  env:: tk.environment.new(
    name='environments/gateway',
    namespace='istio-system',
    apiserver='',
  ) + tk.environment.withData($.data),

  envs: {
    certificates: $.env,
  },
}
