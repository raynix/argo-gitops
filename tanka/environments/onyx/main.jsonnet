local tk = import 'tanka-util/main.libsonnet';
local sites = std.parseYaml(importstr '../apps.yaml');
local util = import 'my-util.libsonnet';

local defaults = {
  nfs_ip: '192.168.1.51',
  nfs_path_base: '/var/nfs/k8s/',
  replicas: 2,
  history: 3,
  volume_size: '10Gi',
};

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
