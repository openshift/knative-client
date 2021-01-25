package cmd

import (
	"fmt"

	"github.com/ory/viper"
	"github.com/spf13/cobra"

	bosonFunc "github.com/boson-project/func"
	"github.com/boson-project/func/docker"
)

func init() {
	// Add the run command as a subcommand of root.
	root.AddCommand(runCmd)
	runCmd.Flags().StringArrayP("env", "e", []string{}, "Environment variable to set in the form NAME=VALUE. You may provide this flag multiple times for setting multiple environment variables.")
	runCmd.Flags().StringP("path", "p", cwd(), "Path to the project directory (Env: $FUNC_PATH)")
}

var runCmd = &cobra.Command{
	Use:   "run",
	Short: "Run the function locally",
	Long: `Run the function locally

Runs the function locally in the current directory or in the directory
specified by --path flag. The function must already have been built with the 'build' command.
`,
	Example: `
# Build function's image first
kn func build

# Run it locally as a container
kn func run
`,
	SuggestFor: []string{"rnu"},
	PreRunE:    bindEnv("path"),
	RunE:       runRun,
}

func runRun(cmd *cobra.Command, args []string) (err error) {
	config := newRunConfig(cmd)

	function, err := bosonFunc.NewFunction(config.Path)
	if err != nil {
		return
	}

	function.EnvVars = mergeEnvVarsMaps(function.EnvVars, config.EnvVars)

	err = function.WriteConfig()
	if err != nil {
		return
	}

	// Check if the Function has been initialized
	if !function.Initialized() {
		return fmt.Errorf("the given path '%v' does not contain an initialized function", config.Path)
	}

	runner := docker.NewRunner()
	runner.Verbose = config.Verbose

	client := bosonFunc.New(
		bosonFunc.WithRunner(runner),
		bosonFunc.WithVerbose(config.Verbose))

	return client.Run(config.Path)
}

type runConfig struct {
	// Path of the Function implementation on local disk. Defaults to current
	// working directory of the process.
	Path string

	// Verbose logging.
	Verbose bool

	EnvVars map[string]string
}

func newRunConfig(cmd *cobra.Command) runConfig {
	return runConfig{
		Path:    viper.GetString("path"),
		Verbose: viper.GetBool("verbose"), // defined on root
		EnvVars: envVarsFromCmd(cmd),
	}
}
