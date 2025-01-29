local tk = import 'tanka-util/main.libsonnet';
local wp = import 'wordpress/main.libsonnet';
local manifests = std.parseYaml(importstr '../apps.yaml');
local secrets = import 'ss.json';

function(name) {
  data(app):: wp {
    _config+:: {
      name: app.name,
      domain: app.domain,
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
    for app in manifests.wordpress
    if app.name == name
  },
}
