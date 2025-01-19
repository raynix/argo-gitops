local tk = import 'tanka-util/main.libsonnet';
local sites = std.parseYaml(importstr '../apps.yaml');
local util = import 'my-util.libsonnet';

function(name) {
  local app_id(app) = '%s-%s' % [app.type, app.name],

  data:: {
    [app_id(app)]: util.argocd_application(app)
    for app in sites
  },

  env:: tk.environment.new(
    name='environments/onyx',
    namespace='argocd',
    apiserver='',
  ) + tk.environment.withData($.data),

  envs: {
    onyx: $.env,
  },
}
