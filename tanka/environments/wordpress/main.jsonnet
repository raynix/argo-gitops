local tk = import 'tanka-util/main.libsonnet';
local wp = import 'wordpress/main.libsonnet';
local sites = std.parseYaml(importstr '../apps.yaml');
local secrets = import 'ss.json';

local defaults = {
  nfs_ip: '192.168.1.51',
  nfs_path_base: '/var/nfs/k8s/',
  replicas: 2,
  history: 3,
  volume_size: '10Gi',
};

function(name) {
  data(app):: wp {
    _config+:: {
      wordpress+: {
        name: app.name,
        replicas: 2,
        domain: app.domain,
        nfs_ip: defaults.nfs_ip,
        nfs_path_base: defaults.nfs_path_base,
        volume_size: defaults.volume_size,
      },
    },

    sealed_secret: secrets[app.name],
  },

  env(app):: tk.environment.new(
    name='environments/' + app.name,
    namespace='wordpress-' + app.name,
    apiserver='',
  ) + tk.environment.withData($.data(app)),

  envs: {
    [app.name]: $.env(app)
    for app in sites
    if app.name == name
  },
}
