// Copyright © 2019 The Knative Authors
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

package traffic

import (
	"github.com/knative/serving/pkg/apis/serving/v1alpha1"
	"gotest.tools/assert"

	"testing"

	"github.com/knative/client/pkg/kn/commands/flags"
	"github.com/spf13/cobra"
)

type trafficTestCase struct {
	name             string
	existingTraffic  []v1alpha1.TrafficTarget
	inputFlags       []string
	desiredRevisions []string
	desiredTags      []string
	desiredPercents  []int
}

type trafficErrorTestCase struct {
	name            string
	existingTraffic []v1alpha1.TrafficTarget
	inputFlags      []string
	errMsg          string
}

func newTestTrafficCommand() (*cobra.Command, *flags.Traffic) {
	var trafficFlags flags.Traffic
	trafficCmd := &cobra.Command{
		Use:   "kn",
		Short: "Traffic test kn command",
		Run:   func(cmd *cobra.Command, args []string) {},
	}
	trafficFlags.Add(trafficCmd)
	return trafficCmd, &trafficFlags
}

func TestCompute(t *testing.T) {
	for _, testCase := range []trafficTestCase{
		{
			"assign 'latest' tag to @latest revision",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("", "", 100, true)),
			[]string{"--tag", "@latest=latest"},
			[]string{"@latest"},
			[]string{"latest"},
			[]int{100},
		},
		{
			"assign tag to revision",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("", "echo-v1", 100, false)),
			[]string{"--tag", "echo-v1=stable"},
			[]string{"echo-v1"},
			[]string{"stable"},
			[]int{100},
		},
		{
			"re-assign same tag to same revision (unchanged)",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("current", "", 100, true)),
			[]string{"--tag", "@latest=current"},
			[]string{"@latest"},
			[]string{"current"},
			[]int{100},
		},
		{
			"split traffic to tags",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("", "", 100, true), newTarget("", "rev-v1", 0, false)),
			[]string{"--traffic", "@latest=10,rev-v1=90"},
			[]string{"@latest", "rev-v1"},
			[]string{"", ""},
			[]int{10, 90},
		},
		{
			"split traffic to tags with '%' suffix",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("", "", 100, true), newTarget("", "rev-v1", 0, false)),
			[]string{"--traffic", "@latest=10%,rev-v1=90%"},
			[]string{"@latest", "rev-v1"},
			[]string{"", ""},
			[]int{10, 90},
		},
		{
			"add 2 more tagged revisions without giving them traffic portions",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("latest", "", 100, true)),
			[]string{"--tag", "@latest=current,echo-v0=stale,echo-v1=old"},
			[]string{"@latest", "echo-v0", "echo-v1"},
			[]string{"current", "stale", "old"},
			[]int{100, 0, 0},
		},
		{
			"re-assign same tag to 'echo-v1' revision",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("latest", "echo-v1", 100, false)),
			[]string{"--tag", "echo-v1=latest"},
			[]string{"echo-v1"},
			[]string{"latest"},
			[]int{100},
		},
		{
			"set 2% traffic to latest revision by appending it in traffic block",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("latest", "echo-v1", 100, false)),
			[]string{"--traffic", "@latest=2,echo-v1=98"},
			[]string{"echo-v1", "@latest"},
			[]string{"latest", ""},
			[]int{98, 2},
		},
		{
			"set 2% to @latest with tag (append it in traffic block)",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("latest", "echo-v1", 100, false)),
			[]string{"--traffic", "@latest=2,echo-v1=98", "--tag", "@latest=testing"},
			[]string{"echo-v1", "@latest"},
			[]string{"latest", "testing"},
			[]int{98, 2},
		},
		{
			"change traffic percent of an existing revision in traffic block, add new revision with traffic share",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("v1", "echo-v1", 100, false)),
			[]string{"--tag", "echo-v2=v2", "--traffic", "v1=10,v2=90"},
			[]string{"echo-v1", "echo-v2"},
			[]string{"v1", "v2"},
			[]int{10, 90}, //default value,
		},
		{
			"untag 'latest' tag from 'echo-v1' revision",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("latest", "echo-v1", 100, false)),
			[]string{"--untag", "latest"},
			[]string{"echo-v1"},
			[]string{""},
			[]int{100},
		},
		{
			"replace revision pointing to 'latest' tag from 'echo-v1' to 'echo-v2' revision",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("latest", "echo-v1", 50, false), newTarget("", "echo-v2", 50, false)),
			[]string{"--untag", "latest", "--tag", "echo-v1=old,echo-v2=latest"},
			[]string{"echo-v1", "echo-v2"},
			[]string{"old", "latest"},
			[]int{50, 50},
		},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			if lper, lrev, ltag := len(testCase.desiredPercents), len(testCase.desiredRevisions), len(testCase.desiredTags); lper != lrev || lper != ltag {
				t.Fatalf("length of desird revisions, tags and percents is mismatched: got=(desiredPercents, desiredRevisions, desiredTags)=(%d, %d, %d)",
					lper, lrev, ltag)
			}

			testCmd, tFlags := newTestTrafficCommand()
			testCmd.SetArgs(testCase.inputFlags)
			testCmd.Execute()
			err, targets := Compute(testCmd, testCase.existingTraffic, tFlags)
			if err != nil {
				t.Fatal(err)
			}
			for i, target := range targets {
				if testCase.desiredRevisions[i] == "@latest" {
					assert.Equal(t, *target.LatestRevision, true)
				} else {
					assert.Equal(t, target.RevisionName, testCase.desiredRevisions[i])
				}
				assert.Equal(t, target.Tag, testCase.desiredTags[i])
				assert.Equal(t, target.Percent, testCase.desiredPercents[i])
			}
		})
	}
}

func TestComputeErrMsg(t *testing.T) {
	for _, testCase := range []trafficErrorTestCase{
		{
			"invalid format for --traffic option",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("", "", 100, true)),
			[]string{"--traffic", "@latest=100=latest"},
			"expecting the value format in value1=value2, given @latest=100=latest",
		},
		{
			"invalid format for --tag option",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("", "", 100, true)),
			[]string{"--tag", "@latest="},
			"expecting the value format in value1=value2, given @latest=",
		},
		{
			"repeatedly spliting traffic to @latest revision",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("", "", 100, true)),
			[]string{"--traffic", "@latest=90,@latest=10"},
			"repetition of identifier @latest is not allowed, use only once with --traffic flag",
		},
		{
			"repeatedly tagging to @latest revision not allowed",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("", "", 100, true)),
			[]string{"--tag", "@latest=latest,@latest=2"},
			"repetition of identifier @latest is not allowed, use only once with --tag flag",
		},
		{
			"overwriting tag to @latest revision not allowed",
			append(append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("latest", "", 2, true)), newTarget("stable", "echo-v2", 98, false)),
			[]string{"--tag", "@latest=stable"},
			"refusing to overwrite existing tag in service, add flag '--untag stable' in command to untag it",
		},
		{
			"overwriting tags of others revisions not allowed",
			append(append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("latest", "", 2, true)), newTarget("stable", "echo-v2", 98, false)),
			[]string{"--tag", "echo-v2=latest"},
			"refusing to overwrite existing tag in service, add flag '--untag latest' in command to untag it",
		},
		{
			"verify error for non integer values given to percent",
			append(newServiceTraffic([]v1alpha1.TrafficTarget{}), newTarget("", "", 100, true)),
			[]string{"--traffic", "@latest=100p"},
			"error converting given 100p to integer value for traffic distribution",
		},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			testCmd, tFlags := newTestTrafficCommand()
			testCmd.SetArgs(testCase.inputFlags)
			testCmd.Execute()
			err, _ := Compute(testCmd, testCase.existingTraffic, tFlags)
			assert.Error(t, err, testCase.errMsg)
		})
	}
}
