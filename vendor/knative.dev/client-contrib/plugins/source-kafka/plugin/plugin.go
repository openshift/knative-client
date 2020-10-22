// Copyright © 2020 The Knative Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package plugin

import (
	"knative.dev/client-contrib/plugins/source-kafka/pkg"
	"os"

	"knative.dev/client/pkg/kn/plugin"
)

func init() {
	plugin.InternalPlugins = append(plugin.InternalPlugins, &sourceKafkaPlugin{})
}

type sourceKafkaPlugin struct {}

func (l *sourceKafkaPlugin) Name() string {
	return "kn-source-kafka"
}

func (l *sourceKafkaPlugin) Execute(args []string) error {
	cmd := pkg.NewSourceKafkaCommand()
	oldArgs := os.Args
	defer (func() {
		os.Args = oldArgs
	})()
	os.Args = append([]string { "kn-source-kafka" }, args...)
	return cmd.Execute()
}

func (l *sourceKafkaPlugin) Description() (string, error) {
	return "Manage Kafka event source", nil
}

func (l *sourceKafkaPlugin) CommandParts() []string {
	return []string{ "source", "kafka" }
}

// Path is empty because its an internal plugins
func (l *sourceKafkaPlugin) Path() string {
	return ""
}
