module knative.dev/client

go 1.14

require (
	github.com/boson-project/faas v0.0.0-00010101000000-000000000000
	github.com/maximilien/kn-source-pkg v0.5.0
	github.com/mitchellh/go-homedir v1.1.0
	github.com/pkg/errors v0.9.1
	github.com/spf13/cobra v1.0.1-0.20201006035406-b97b5ead31f7
	github.com/spf13/pflag v1.0.5
	github.com/spf13/viper v1.7.0
	golang.org/x/crypto v0.0.0-20200820211705-5c72a883971a
	gotest.tools v2.2.0+incompatible
	k8s.io/api v0.18.8
	k8s.io/apimachinery v0.19.1
	k8s.io/cli-runtime v0.18.8
	k8s.io/client-go v11.0.1-0.20190805182717-6502b5e7b1b5+incompatible
	k8s.io/code-generator v0.18.8
	knative.dev/eventing v0.18.5-0.20201105155307-650096a39064
	knative.dev/kn-plugin-source-kafka v0.0.0-20201203183209-e1f755efaca3
	knative.dev/networking v0.0.0-20200922180040-a71b40c69b15
	knative.dev/pkg v0.0.0-20201026165741-2f75016c1368
	knative.dev/serving v0.18.0
	sigs.k8s.io/yaml v1.2.0
)

// Temporary pinning certain libraries. Please check periodically, whether these are still needed
// ----------------------------------------------------------------------------------------------
replace (
	k8s.io/api => k8s.io/api v0.18.8
	k8s.io/apiextensions-apiserver => k8s.io/apiextensions-apiserver v0.18.8
	k8s.io/apimachinery => k8s.io/apimachinery v0.18.8
	k8s.io/cli-runtime => k8s.io/cli-runtime v0.18.8
	k8s.io/client-go => k8s.io/client-go v0.18.8
	k8s.io/code-generator => k8s.io/code-generator v0.18.8
)

replace (
	github.com/boson-project/faas => github.com/boson-project/faas v0.9.1-0.20201125171548-557361a37446

	// Pin conflicting dependency versions
	// Buildpacks required version
	github.com/docker/docker => github.com/docker/docker v1.4.2-0.20200221181110-62bd5a33f707
	// Darwin cross-build required version
	golang.org/x/sys => golang.org/x/sys v0.0.0-20200302150141-5c8b2ff67527
)
