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

package flags

import (
	"github.com/spf13/cobra"
)

type Traffic struct {
	RevisionsPercentages []string
	RevisionsTags        []string
	UntagRevisions       []string
}

func (t *Traffic) Add(cmd *cobra.Command) {
	cmd.Flags().StringSliceVar(&t.RevisionsPercentages,
		"traffic",
		nil,
		"Set traffic percentage, format: --traffic revision=percent , example: --traffic echo-abcde=50) (can be specified multiple times). "+
			"Use identifier @latest to refer to latest ready revision, for e.g.: --traffic LATEST=100 (LATEST can be used only once with --traffic flag).")

	cmd.Flags().StringSliceVar(&t.RevisionsTags,
		"tag",
		nil,
		"Tag revisions, format: --tag revision=tag , example: --tag echo-abcde=current (can be specified multiple times). "+
			"Use identifier @latest to refer to latest ready revision, for e.g.: --tag LATEST=new (LATEST can be used only once with --tag flag).")

	cmd.Flags().StringSliceVar(&t.UntagRevisions,
		"untag",
		nil,
		"Untag revision, format: --untag tag , example: --untag current")
}

func (t *Traffic) PercentagesChanged(cmd *cobra.Command) bool {
	if cmd.Flags().Changed("traffic") {
		return true
	}

	return false
}

func (t *Traffic) TagsChanged(cmd *cobra.Command) bool {
	switch {
	case cmd.Flags().Changed("tag"):
		return true
	case cmd.Flags().Changed("untag"):
		return true
	default:
		return false
	}
}

func (t *Traffic) Changed(cmd *cobra.Command) bool {
	if t.PercentagesChanged(cmd) || t.TagsChanged(cmd) {
		return true
	}
	return false
}
