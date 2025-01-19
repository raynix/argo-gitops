local k = import '../k.libsonnet';
{
  _config:: {
    wordpress: {
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
  },

  local myutil = import '../my-util.libsonnet',
  local namespace = k.core.v1.namespace,
  local cm = k.core.v1.configMap,
  local c = $._config.wordpress,
  local cron = k.batch.v1.cronJob,
  local deploy = k.apps.v1.deployment,
  local svc = k.core.v1.service,
  local container = k.core.v1.container,
  local secret_ref = k.core.v1.envFromSource.secretRef,
  local volume_mount = k.core.v1.volumeMount,
  local volume = k.core.v1.volume,
  local volume_www = volume.fromPersistentVolumeClaim('var-www', 'wordpress'),
  local volume_gsa = volume.fromSecret('gcp-sa', 'backup-gcp-sa'),

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
      container.new('wordpress', c.image) +
      container.withEnvFrom([
        secret_ref.withName('wordpress-secret'),
      ]) +
      container.withEnv([
        {
          name: 'WORDPRESS_TABLE_PREFIX',
          value: 'wp_',
        },
      ]) +
      container.withPorts([{ name: 'fpm', containerPort: 9000 }]) +
      container.withVolumeMounts([
        volume_mount.new('php-config-volume', '/usr/local/etc/php/php.ini') +
        volume_mount.withSubPath('php.ini'),
        volume_mount.new(volume_www.name, '/var/www/html'),
      ]) +
      container.resources.withRequests({ cpu: '400m', memory: '400Mi' }) +
      myutil.readiness_probe('fpm') +
      myutil.liveness_probe('fpm'),
      // nginx container
      container.new('nginx', c.nginx) +
      container.withPorts([{ name: 'http', containerPort: 8080 }]) +
      container.withVolumeMounts([
        volume_mount.new('wordpress-nginx-config-volume', '/etc/nginx/conf.d'),
        volume_mount.new('nginx-config-volume', '/etc/nginx/nginx.conf') +
        volume_mount.withSubPath('nginx.conf'),
        volume_mount.new(volume_www.name, '/var/www/html'),
      ]) +
      container.resources.withRequests({ cpu: '100m', memory: '100Mi' }) +
      myutil.readiness_probe('http') +
      myutil.liveness_probe('http'),
    ], { domain: c.domain }) +
    deploy.spec.withRevisionHistoryLimit(c.history) +
    deploy.spec.strategy.withType('RollingUpdate') +
    deploy.spec.strategy.rollingUpdate.withMaxSurge('50%') +
    deploy.spec.strategy.rollingUpdate.withMaxUnavailable(0) +
    deploy.spec.template.spec.securityContext.withRunAsUser(65534) +
    deploy.spec.template.spec.securityContext.withRunAsGroup(65534) +
    deploy.spec.template.spec.affinity.podAntiAffinity.withPreferredDuringSchedulingIgnoredDuringExecution([
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
    ]) +
    deploy.spec.template.spec.withVolumes([
      volume.fromConfigMap('nginx-config-volume', $.nginx_config.metadata.name),
      volume.fromConfigMap('wordpress-nginx-config-volume', $.wp_config.metadata.name),
      volume.fromConfigMap('php-config-volume', $.php_config.metadata.name),
      volume_www,
    ]),

  service:
    svc.new($.deploy.metadata.name, $.deploy.spec.selector.matchLabels, [
      { name: 'http-wp', port: 8080, targetPort: 8080 },
    ]),

  certificate: myutil.certificate(c.name, 'istio-system', [c.domain]),

  http_route: myutil.http_route($.service.metadata.name, c.domain, 'kubernetes-gateway'),

  redis_deploy:
    deploy.new('redis', 1, [
      container.new('redis', c.redis) +
      container.withPorts([{ name: 'redis', containerPort: 6379 }]) +
      myutil.readiness_probe('redis') +
      myutil.liveness_probe('redis') +
      container.resources.withRequests({ cpu: '100m', memory: '400Mi' }) +
      container.resources.withLimits({ cpu: '1.0', memory: '1Gi' }),
    ], { app: 'redis' }),

  redis_service:
    svc.new($.redis_deploy.metadata.name, $.redis_deploy.spec.selector.matchLabels, [
      { name: 'tcp-redis', port: 6379, targetPort: 6379 },
    ]),

}
