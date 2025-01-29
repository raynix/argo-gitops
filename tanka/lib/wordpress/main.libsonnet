local k = import 'ksonnet-util/kausal.libsonnet';

{
  _config:: {
    name: 'wp',
    replicas: 2,
    history: 3,
    image: 'wordpress:php8.1-fpm-alpine',
    nginx: 'nginx:1.22.1',
    redis: 'redis:6.2.8-alpine3.17',
    backup: 'ghcr.io/raynix/backup:v0.37',
    domain: 'changeme.com',
    nfs_base_path: '/var/nfs/k8s/',
    volume_ip: '192.168.1.51',
    volume_size: '10Gi',
    istio: false,
    dynamic_volume: false,
  },

  local myutil = import '../my-util.libsonnet',
  local namespace = k.core.v1.namespace,
  local cm = k.core.v1.configMap,
  local c = $._config,
  local cron = k.batch.v1.cronJob,
  local deploy = k.apps.v1.deployment,
  local svc = k.core.v1.service,
  local container = k.core.v1.container,
  local secret_ref = k.core.v1.envFromSource.secretRef,
  local volume_mount = k.core.v1.volumeMount,
  local volume = k.core.v1.volume,

  local labels = {
    app: 'wordpress',
    domain: c.domain,
  },

  namespace: namespace.new('wordpress-' + c.name),

  nginx_config: cm.new('nginx-config', { 'nginx.conf': importstr 'conf/nginx.conf' }),
  php_config: cm.new('php-config', { 'php.ini': importstr 'conf/php.ini' }),
  wp_config: cm.new('wordpress-nginx-config', { 'wordpress-nginx.conf': importstr 'conf/wordpress-nginx.conf' }),

  wp_volume: if c.dynamic_volume then myutil.dynamic_volume(c.name, $.namespace.metadata.name) {
    volume_size: c.volume_size,
  } else myutil.static_volume(c.name, $.namespace.metadata.name) {
    volume_ip: c.volume_ip,
    volume_path: c.nfs_base_path + c.domain,
    volume_size: c.volume_size,
  },

  local volume_www = volume.fromPersistentVolumeClaim('var-www', $.wp_volume.pvc.metadata.name),
  local volume_gsa = volume.fromSecret('gcp-sa', 'backup-gcp-sa'),

  backup_job:
    cron.new('backup', '0 14 * * 0', [
      container.new('backup-tool', c.backup) +
      container.withCommand(['/bin/bash', '-c', '/wordpress.sh %s /wordpress /gcp/${SERVICE_ACCOUNT_KEY} ${BACKUP_BUCKET}' % [c.domain]]) +
      container.withEnvFrom([
        secret_ref.withName('wordpress-secret'),
        secret_ref.withName('backup-gcp-env'),
      ]) +
      container.withVolumeMounts([
        volume_mount.new(volume_www.name, '/wordpress'),
        volume_mount.new(volume_gsa.name, '/gcp'),
      ]),
    ]) +
    cron.spec.jobTemplate.spec.template.spec.withRestartPolicy('Never') +
    cron.spec.jobTemplate.spec.template.spec.securityContext.withRunAsUser(65534) +
    cron.spec.jobTemplate.spec.template.spec.securityContext.withRunAsGroup(65534) +
    cron.spec.jobTemplate.spec.template.spec.withVolumes([volume_www, volume_gsa]) +
    cron.spec.jobTemplate.spec.template.metadata.withAnnotations({ 'sidecar.istio.io/inject': 'false' }),

  deploy:
    deploy.new('wordpress', c.replicas, [
      // wordpress-php-fpm container
      container.new('wordpress', c.image) {
        envFrom: [
          {
            secretRef: {
              name: 'wordpress-secret',
            },
          },
        ],
        env: [
          {
            name: 'WORDPRESS_TABLE_PREFIX',
            value: 'wp_',
          },
        ],
        ports: [
          {
            name: 'fpm',
            containerPort: 9000,
            protocol: 'TCP',
          },
        ],
        volumeMounts: [
          {
            name: 'php-config-volume',
            mountPath: '/usr/local/etc/php/php.ini',
            subPath: 'php.ini',
          },
          {
            name: volume_www.name,
            mountPath: '/var/www/html',
          },
        ],
        resources: {
          requests: {
            cpu: '400m',
            memory: '400Mi',
          },
        },
      },
      // nginx container
      container.new('nginx', c.nginx) {
        ports: [
          {
            name: 'http',
            containerPort: 8080,
            protocol: 'TCP',
          },
        ],
        volumeMounts: [
          {
            name: 'wordpress-nginx-config-volume',
            mountPath: '/etc/nginx/conf.d',
          },
          {
            name: 'nginx-config-volume',
            mountPath: '/etc/nginx/nginx.conf',
            subPath: 'nginx.conf',
          },
          {
            name: volume_www.name,
            mountPath: '/var/www/html',
          },
        ],
        resources: {
          requests: {
            cpu: '100m',
            memory: '100Mi',
          },
        },
        readinessProbe: myutil.http_probe('http', '/wp-login.php'),
        livenessProbe: myutil.http_probe('http', '/wp-login.php'),
      },
    ], { domain: c.domain }) {
      spec+: {
        revisionHistoryLimit: c.history,
        strategy: {
          type: 'RollingUpdate',
          rollingUpdate: {
            maxSurge: '50%',
            maxUnavailable: 0,
          },
        },
        template+: {
          spec+: {
            securityContext: {
              runAsUser: 65534,
              runAsGroup: 65534,
            },
            affinity: {
              podAntiAffinity: {
                preferredDuringSchedulingIgnoredDuringExecution: [
                  {
                    weight: 100,
                    podAffinityTerm: {
                      labelSelector: {
                        matchExpressions: [
                          {
                            key: 'app',
                            operator: 'In',
                            values: ['wordpress'],
                          },
                          {
                            key: 'domain',
                            operator: 'In',
                            values: [c.domain],
                          },
                        ],
                      },
                      topologyKey: 'kubernetes.io/hostname',
                    },
                  },
                ],
              },
            },
            volumes: [
              volume.fromConfigMap('nginx-config-volume', $.nginx_config.metadata.name),
              volume.fromConfigMap('wordpress-nginx-config-volume', $.wp_config.metadata.name),
              volume.fromConfigMap('php-config-volume', $.php_config.metadata.name),
              volume_www,
            ],
          },
        },
      },
    },

  service: k.util.serviceFor($.deploy),

  http_route: myutil.http_route($.service, c.domain, 'kubernetes-gateway', port_name='nginx-http'),

  redis_deploy:
    deploy.new('redis', 1, [
      container.new('redis', c.redis) {
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
}
