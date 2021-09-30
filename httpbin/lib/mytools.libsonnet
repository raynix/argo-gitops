local mytools(k) = {
    gatewayFor(name, tls_secret, hosts=[], selector="ingressgateway")::
        {
            apiVersion: 'networking.istio.io/v1beta1',
            kind: 'Gateway',
            metadata: {
                name: name
            },
            spec: {
                selector: {
                    istio: selector
                },
                servers: [
                    {
                        hosts: hosts,
                        port: {
                            name: 'https',
                            number: 443,
                            protocol: 'HTTPS'
                        },
                        tls: {
                            mode: 'SIMPLE',
                            credentialName: tls_secret
                        },
                    },
                    {
                        hosts: hosts,
                        port: {
                            name: 'http',
                            number: 80,
                            protocol: 'HTTP'
                        },
                        tls: {
                            httpsRedirect: true,
                        },
                    },
                ],
            },

        },
    virtualServiceFor(gateway, service, hosts=[])::
        {
            apiVersion: 'networking.istio.io/v1beta1',
            kind: 'VirtualService',
            metadata: {
                name: gateway,
            },
            spec: {
                gateways: [
                    gateway,
                ],

                hosts: hosts,
                http: [
                    {
                        route: [
                            {
                                destination: {
                                    host: service
                                },
                            },
                        ],
                    },

                ],
            },
        },

};

mytools((import 'grafana.libsonnet')) + {
    withK(k):: mytools(k),
}