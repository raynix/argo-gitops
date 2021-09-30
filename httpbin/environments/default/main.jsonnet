(import "httpbin.libsonnet") +
{
  _config:: {
    httpbin: {
      port: 80,
      name: "httpbin",
      image: "kennethreitz/httpbin:latest",
    }
  },
}
