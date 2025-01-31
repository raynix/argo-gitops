local util = import 'my-util.libsonnet';
local tk = import 'tanka-util/main.libsonnet';
local manifests = std.parseYaml(importstr '../apps.yaml');
local helms = std.parseYaml(importstr '../helms.yaml');
local apps = [
  i { type: k }
  for k in std.objectFields(manifests)
  for i in manifests[k]
] + [
  i { type: 'helm' }
  for i in helms
];

function(name) {
  local app_id(app) = '%s-%s' % [app.type, app.name],

  data:: {
    [app_id(app)]: util.argocd_application(app)
    for app in apps
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
