module knative.dev/client

go 1.15

require (
	github.com/boson-project/func v0.15.2-0.20210615072636-a937c490b7e1
	github.com/google/go-cmp v0.5.5
	github.com/mitchellh/go-homedir v1.1.0
	github.com/spf13/cobra v1.1.3
	github.com/spf13/pflag v1.0.5
	github.com/spf13/viper v1.7.1
	golang.org/x/term v0.0.0-20201210144234-2321bbc49cbf
	gotest.tools/v3 v3.0.3
	k8s.io/api v0.19.7
	k8s.io/apimachinery v0.19.7
	k8s.io/cli-runtime v0.19.7
	k8s.io/client-go v0.19.7
	k8s.io/code-generator v0.20.1
	knative.dev/eventing v0.22.0
	knative.dev/hack v0.0.0-20210325223819-b6ab329907d3
	knative.dev/kn-plugin-source-kafka v0.22.0
	knative.dev/networking v0.0.0-20210331064822-999a7708876c
	knative.dev/pkg v0.0.0-20210331065221-952fdd90dbb0
	knative.dev/serving v0.22.0
	sigs.k8s.io/yaml v1.2.0
)

replace (
	github.com/go-openapi/spec => github.com/go-openapi/spec v0.19.3
	k8s.io/code-generator => k8s.io/code-generator v0.19.7
)
