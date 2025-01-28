local k = import 'ksonnet-util/kausal.libsonnet';
local myutil = import 'my-util.libsonnet';

function(name='postiz') {
  _config:: {
    port: 5000,
    image: 'ghcr.io/gitroomhq/postiz-app:v1.31.1-amd64',
    host: 'postiz.awes.one',
  },

  local namespace = k.core.v1.namespace,
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,

  namespace: namespace.new(name),
  pvc: myutil.dynamic_volume(name, name) { volume_size: '10Gi' },

  deployment: deployment.new(
    name=name,
    replicas=1,
    containers=[
      container.new(name, $._config.image) {
        ports: [
          { name: name, containerPort: $._config.port, protocol: 'TCP' },
        ],
        resources: {
          requests: {
            cpu: '500m',
            memory: '500Mi',
          },
          limits: {
            cpu: '1',
            memory: '2Gi',
          },
        },
        livenessProbe: myutil.http_probe(name, '/'),
        readinessProbe: myutil.http_probe(name, '/'),
        volumeMounts: [
          {
            name: 'postiz-config-volume',
            mountPath: '/config/.env',
            subPath: '.env',
          },
          {
            name: 'postiz-uploads',
            mountPath: '/uploads',
          },
        ],
      },
    ],
  ) {
    spec+: {
      template+: {
        spec+: {
          volumes: [
            {
              name: 'postiz-config-volume',
              secret: {
                secretName: 'postiz',
              },
            },
            {
              name: 'postiz-uploads',
              persistentVolumeClaim: {
                claimName: $.pvc.pvc.metadata.name,
              },
            },
          ],
        },
      },
    },
  },

  service: k.util.serviceFor($.deployment),

  redis_deploy:
    deployment.new('redis', 1, [
      container.new('redis', 'redis:7.2') {
        ports: [
          {
            name: 'redis',
            containerPort: 6379,
            protocol: 'TCP',
          },
        ],
        resources: {
          requests: {
            cpu: '100m',
            memory: '400Mi',
          },
          limits: {
            cpu: '500m',
            memory: '1Gi',
          },

        },
        readinessProbe: myutil.tcp_probe('redis'),
        livenessProbe: myutil.tcp_probe('redis'),
      },
    ], { app: 'redis' }),

  redis_service: k.util.serviceFor($.redis_deploy),

  http_route: myutil.http_route($.service, $._config.host, 'kubernetes-gateway'),
}
