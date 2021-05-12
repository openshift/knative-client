module knative.dev/client

go 1.15

require (
	github.com/boson-project/func v0.14.0
	github.com/google/go-cmp v0.5.5
	github.com/maximilien/kn-source-pkg v0.6.3
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
	knative.dev/eventing v0.21.0
	knative.dev/hack v0.0.0-20210203173706-8368e1f6eacf
	knative.dev/kn-plugin-source-kafka v0.21.0
	knative.dev/networking v0.0.0-20210216014426-94bfc013982b
	knative.dev/pkg v0.0.0-20210216013737-584933f8280b
	knative.dev/serving v0.21.0
	sigs.k8s.io/yaml v1.2.0
)

replace (
	github.com/go-openapi/spec => github.com/go-openapi/spec v0.19.3
	k8s.io/code-generator => k8s.io/code-generator v0.19.7
)
