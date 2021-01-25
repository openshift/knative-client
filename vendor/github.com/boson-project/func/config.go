package function

import (
	"io/ioutil"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v2"
)

// ConfigFile is the name of the config's serialized form.
const ConfigFile = "func.yaml"

// Config represents the serialized state of a Function's metadata.
// See the Function struct for attribute documentation.
type config struct {
	Name        string            `yaml:"name"`
	Namespace   string            `yaml:"namespace"`
	Runtime     string            `yaml:"runtime"`
	Image       string            `yaml:"image"`
	ImageDigest string            `yaml:"imageDigest"`
	Trigger     string            `yaml:"trigger"`
	Builder     string            `yaml:"builder"`
	BuilderMap  map[string]string `yaml:"builderMap"`
	EnvVars     map[string]string `yaml:"envVars"`
	// Add new values to the toConfig/fromConfig functions.
}

// newConfig returns a Config populated from data serialized to disk if it is
// available.  Errors are returned if the path is not valid, if there are
// errors accessing an extant config file, or the contents of the file do not
// unmarshall.  A missing file at a valid path does not error but returns the
// empty value of Config.
func newConfig(root string) (c config, err error) {
	filename := filepath.Join(root, ConfigFile)
	if _, err = os.Stat(filename); err != nil {
		// do not consider a missing config file an error.  Just return.
		if os.IsNotExist(err) {
			err = nil
		}
		return
	}
	bb, err := ioutil.ReadFile(filename)
	if err != nil {
		return
	}
	err = yaml.Unmarshal(bb, &c)
	return
}

// fromConfig returns a Function populated from config.
// Note that config does not include ancillary fields not serialized, such as Root.
func fromConfig(c config) (f Function) {
	return Function{
		Name:        c.Name,
		Namespace:   c.Namespace,
		Runtime:     c.Runtime,
		Image:       c.Image,
		ImageDigest: c.ImageDigest,
		Trigger:     c.Trigger,
		Builder:     c.Builder,
		BuilderMap:  c.BuilderMap,
		EnvVars:     c.EnvVars,
	}
}

// toConfig serializes a Function to a config object.
func toConfig(f Function) config {
	return config{
		Name:        f.Name,
		Namespace:   f.Namespace,
		Runtime:     f.Runtime,
		Image:       f.Image,
		ImageDigest: f.ImageDigest,
		Trigger:     f.Trigger,
		Builder:     f.Builder,
		BuilderMap:  f.BuilderMap,
		EnvVars:     f.EnvVars,
	}
}

// writeConfig for the given Function out to disk at root.
func writeConfig(f Function) (err error) {
	path := filepath.Join(f.Root, ConfigFile)
	c := toConfig(f)
	var bb []byte
	if bb, err = yaml.Marshal(&c); err != nil {
		return
	}
	return ioutil.WriteFile(path, bb, 0644)
}
