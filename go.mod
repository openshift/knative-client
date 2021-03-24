module knative.dev/client

go 1.14

require (
	github.com/boson-project/func v0.11.1-0.20210322141803-dc2fbee67f7f
	github.com/google/go-cmp v0.5.4
	github.com/maximilien/kn-source-pkg v0.6.1
	github.com/mitchellh/go-homedir v1.1.0
	github.com/pkg/errors v0.9.1
	github.com/spf13/cobra v1.1.3
	github.com/spf13/pflag v1.0.5
	github.com/spf13/viper v1.7.0
	golang.org/x/crypto v0.0.0-20201016220609-9e8e0b390897
	gotest.tools v2.2.0+incompatible
	k8s.io/api v0.19.7
	k8s.io/apimachinery v0.19.7
	k8s.io/cli-runtime v0.18.12
	k8s.io/client-go v11.0.1-0.20190805182717-6502b5e7b1b5+incompatible
	k8s.io/code-generator v0.20.1
	knative.dev/eventing v0.20.0
	knative.dev/hack v0.0.0-20210120165453-8d623a0af457
	knative.dev/kn-plugin-source-kafka v0.20.0
	knative.dev/networking v0.0.0-20210107024535-ecb89ced52d9
	knative.dev/pkg v0.0.0-20210122211754-250a1834dbef
	knative.dev/serving v0.20.0
	sigs.k8s.io/yaml v1.2.0
)

// Temporary pinning certain libraries. Please check periodically, whether these are still needed
// ----------------------------------------------------------------------------------------------
replace (
	k8s.io/api => k8s.io/api v0.18.12
	k8s.io/apimachinery => k8s.io/apimachinery v0.18.12
	k8s.io/cli-runtime => k8s.io/cli-runtime v0.18.12
	k8s.io/client-go => k8s.io/client-go v0.18.12
	k8s.io/code-generator => k8s.io/code-generator v0.18.12

	knative.dev/pkg => knative.dev/pkg v0.0.0-20210107022335-51c72e24c179
)

replace k8s.io/apiextensions-apiserver => k8s.io/apiextensions-apiserver v0.18.12
