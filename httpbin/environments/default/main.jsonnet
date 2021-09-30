(import "httpbin.libsonnet") +
{
  _config+:: {
    httpbin: {
      port: 80,
      name: "httpbin",
      image: "kennethreitz/httpbin:latest",
      host: "httpbin.awes.one",
      cert: "awes-one-cert",
    }
  },
}
