# Grafana Deployment
## Deploy
1, Copy .example file to a new file without the .example extension. ie. ingress.yaml.example -> ingress.yaml
2, Put working values into these files. ie. replace localdomain to something meaningful
3, Run `kubectl apply -k .`
