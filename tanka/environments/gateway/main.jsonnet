local tk = import 'tanka-util/main.libsonnet';
local sites = std.parseYaml(importstr '../apps.yaml');
local domains = std.parseYaml(importstr '../domains.yaml');
local util = import 'my-util.libsonnet';

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
