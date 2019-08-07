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
	RevisionsPercentages     []string
	RevisionsTags            []string
	LatestRevisionPercentage int
	LatestRevisionTag        string
	UntagRevisions           []string
}

func (t *Traffic) Add(cmd *cobra.Command) {
	cmd.Flags().StringSliceVar(&t.RevisionsPercentages,
		"traffic",
		nil,
		"Set traffic percentage, format: --traffic revision:percent , example: --traffic echo-abcde:50) (can be specified multiple times)")

	cmd.Flags().StringSliceVar(&t.RevisionsTags,
		"tag-revision",
		nil,
		"Tag revisions, format: --tag-revision revision:tag , example: --tag-revision echo-abcde:current (can be specified multiple times)")

	cmd.Flags().IntVar(&t.LatestRevisionPercentage,
		"traffic-latest",
		0,
		"Set traffic for latest ready revision, format: --traffic-latest percent , example: --traffic-latest 100")

	cmd.Flags().StringVar(&t.LatestRevisionTag,
		"tag-latest",
		"",
		"Tag latest ready revision, format: --tag-latest tag , example: --tag-latest current")

	cmd.Flags().StringSliceVar(&t.UntagRevisions,
		"untag-revision",
		nil,
		"Untag revision, format: --untag-revision tag , example: --untag-revision current")
}

func (t *Traffic) PercentagesChanged(cmd *cobra.Command) bool {
	switch {
	case cmd.Flags().Changed("traffic"):
		return true
	case cmd.Flags().Changed("traffic-latest"):
		return true
	default:
		return false
	}
}

func (t *Traffic) TagsChanged(cmd *cobra.Command) bool {
	switch {
	case cmd.Flags().Changed("tag-revision"):
		return true
	case cmd.Flags().Changed("tag-latest"):
		return true
	case cmd.Flags().Changed("untag-revision"):
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
