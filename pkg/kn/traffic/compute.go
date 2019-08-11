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
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/knative/client/pkg/kn/commands/flags"
	"github.com/knative/pkg/ptr"
	"github.com/knative/serving/pkg/apis/serving/v1alpha1"
	"github.com/spf13/cobra"
)

var latestRevisionRef = "@latest"

type ServiceTraffic []v1alpha1.TrafficTarget

func newServiceTraffic(traffic []v1alpha1.TrafficTarget) ServiceTraffic {
	return ServiceTraffic(traffic)
}

func splitByEqualSign(pair string) (string, string, error) {
	parts := strings.Split(pair, "=")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", "", errors.New(fmt.Sprintf("expecting the value format in value1=value2, given %s", pair))
	}
	return parts[0], strings.TrimSuffix(parts[1], "%"), nil
}

func newTarget(tag, revision string, percent int, latestRevision bool) (target v1alpha1.TrafficTarget) {
	target.Percent = percent
	target.Tag = tag
	if latestRevision {
		target.LatestRevision = ptr.Bool(true)
	} else {
		// as LatestRevision and RevisionName can't be specfied together for a target
		target.LatestRevision = ptr.Bool(false)
		target.RevisionName = revision
	}
	return
}

func (e ServiceTraffic) IsTagPresentOnRevision(tag, revision string) bool {
	for _, target := range e {
		if target.Tag == tag && target.RevisionName == revision {
			return true
		}
	}
	return false
}

func (e ServiceTraffic) IsTagPresentOnLatestRevision(tag string) bool {
	for _, target := range e {
		if target.Tag == tag && *target.LatestRevision {
			return true
		}
	}
	return false
}

func (e ServiceTraffic) IsTagPresent(tag string) bool {
	for _, target := range e {
		if target.Tag == tag {
			return true
		}
	}
	return false
}

func (e ServiceTraffic) UntagRevision(tag string) {
	for i, target := range e {
		if target.Tag == tag {
			e[i].Tag = ""
			break
		}
	}
}

func (e ServiceTraffic) IsRevisionPresent(revision string) bool {
	for _, target := range e {
		if target.RevisionName == revision {
			return true
		}
	}
	return false
}

func (e ServiceTraffic) IsLatestRevisionTrue() bool {
	for _, target := range e {
		if *target.LatestRevision == true {
			return true
		}
	}
	return false
}

func (e ServiceTraffic) TagRevision(tag, revision string) ServiceTraffic {
	for i, target := range e {
		// add new tag in traffic block if referenced revision doesnt have one
		if target.RevisionName == revision {
			e[i].Tag = tag
			return e
		}
	}
	e = append(e, newTarget(tag, revision, 0, false))
	return e
}

func (e ServiceTraffic) TagLatestRevision(tag string) ServiceTraffic {
	for i, target := range e {
		if *target.LatestRevision {
			e[i].Tag = tag
			return e
		}
	}
	e = append(e, newTarget(tag, "", 0, true))
	return e
}

func (e ServiceTraffic) SetTrafficByRevision(revision string, percent int) {
	for i, target := range e {
		if target.RevisionName == revision {
			e[i].Percent = percent
			break
		}
	}
}

func (e ServiceTraffic) SetTrafficByTag(tag string, percent int) {
	for i, target := range e {
		if target.Tag == tag {
			e[i].Percent = percent
			break
		}
	}
}

func (e ServiceTraffic) SetTrafficByLatestRevision(percent int) {
	for i, target := range e {
		if *target.LatestRevision {
			e[i].Percent = percent
			break
		}
	}
}

func (e ServiceTraffic) ResetAllTargetPercent() {
	for i := range e {
		e[i].Percent = 0
	}
}

func (e ServiceTraffic) RemoveNullTargets() (newTraffic ServiceTraffic) {
	for _, target := range e {
		if target.Tag == "" && target.Percent == 0 {
		} else {
			newTraffic = append(newTraffic, target)
		}
	}
	return newTraffic
}

func errorOverWritingTag(tag string) error {
	return errors.New(fmt.Sprintf("refusing to overwrite existing tag in service, "+
		"add flag '--untag %s' in command to untag it", tag))
}

func errorRepeatingLatestRevision(forFlag string) error {
	return errors.New(fmt.Sprintf("repetition of identifier %s "+
		"is not allowed, use only once with %s flag", latestRevisionRef, forFlag))
}

// verifies if user has repeated @latest field in --tag or --traffic flags
// verifyInputSanity checks:
// - if user has repeated @latest field in --tag or --traffic flags
// - if provided traffic portion are integers
func verifyInputSanity(trafficFlags *flags.Traffic) error {
	var latestRevisionTag = false
	var latestRevisionTraffic = false
	var sum = 0

	for _, each := range trafficFlags.RevisionsTags {
		revision, _, err := splitByEqualSign(each)
		if err != nil {
			return err
		}

		if latestRevisionTag && revision == latestRevisionRef {
			return errorRepeatingLatestRevision("--tag")

		}

		if revision == latestRevisionRef {
			latestRevisionTag = true
		}
	}

	for _, each := range trafficFlags.RevisionsPercentages {
		revisionRef, percent, err := splitByEqualSign(each)
		if err != nil {
			return err
		}

		percentInt, err := strconv.Atoi(percent)
		if err != nil {
			return errors.New(fmt.Sprintf("error converting given %s to integer value for traffic distribution", percent))
		}

		if latestRevisionTraffic && revisionRef == latestRevisionRef {
			return errorRepeatingLatestRevision("--traffic")
		}

		if revisionRef == latestRevisionRef {
			latestRevisionTraffic = true
		}

		sum += percentInt
	}

	// equivalent check for `cmd.Flags().Changed("traffic")` as we don't have `cmd` in this function
	if len(trafficFlags.RevisionsPercentages) > 0 && sum != 100 {
		return errors.New(fmt.Sprintf("given traffic percents sum to 80, want 100"))
	}

	return nil
}

func Compute(cmd *cobra.Command, targets []v1alpha1.TrafficTarget, trafficFlags *flags.Traffic) (error, []v1alpha1.TrafficTarget) {
	err := verifyInputSanity(trafficFlags)
	if err != nil {
		return err, nil
	}

	traffic := newServiceTraffic(targets)

	// First precedence: Untag revisions
	for _, tag := range trafficFlags.UntagRevisions {
		traffic.UntagRevision(tag)
	}

	for _, each := range trafficFlags.RevisionsTags {
		revision, tag, _ := splitByEqualSign(each) // err is checked in verifyInputSanity

		// Second precedence: Tag latestRevision
		if revision == latestRevisionRef {
			// apply requested tag only if it doesnt exist in traffic block
			if traffic.IsTagPresent(tag) {
				// dont throw error if the tag present == requested tag
				if traffic.IsTagPresentOnLatestRevision(tag) {
					continue
				}
				// dont overwrite tags
				return errorOverWritingTag(tag), nil

			}

			traffic = traffic.TagLatestRevision(tag)
			continue
		}

		// Third precedence: Tag other revisions
		if traffic.IsTagPresent(tag) {
			// dont throw error if the tag present == requested tag
			if traffic.IsTagPresentOnRevision(tag, revision) {
				continue
			}

			return errorOverWritingTag(tag), nil
		}

		traffic = traffic.TagRevision(tag, revision)
	}

	if cmd.Flags().Changed("traffic") {
		// reset existing traffic portions as what's on CLI is desired state of traffic split portions
		traffic.ResetAllTargetPercent()

		for _, each := range trafficFlags.RevisionsPercentages {
			// revisionRef works here as either revision or tag as either can be specified on CLI
			revisionRef, percent, _ := splitByEqualSign(each) // err is verified in verifyInputSanity
			percentInt, _ := strconv.Atoi(percent)            // percentInt (for int) is verified in verifyInputSanity

			// fourth precedence: set traffic for latest revision
			if revisionRef == latestRevisionRef {
				if traffic.IsLatestRevisionTrue() {
					traffic.SetTrafficByLatestRevision(percentInt)
				} else {
					// if no latestRevision ref is present in traffic block
					traffic = append(traffic, newTarget("", "", percentInt, true))
				}
				continue
			}

			// fifth precedence: set traffic for rest of revisions
			// If in a traffic block, revisionName of one target == tag of another,
			// one having tag is assigned given percent, as tags are supposed to be unique
			// and should be used (in this case) to avoid ambiguity

			// first check if given revisionRef is a tag
			if traffic.IsTagPresent(revisionRef) {
				traffic.SetTrafficByTag(revisionRef, percentInt)
				continue
			}

			// check if given revisionRef is a revision
			if traffic.IsRevisionPresent(revisionRef) {
				traffic.SetTrafficByRevision(revisionRef, percentInt)
				continue
			}

			// TODO Check at serving level, improve error
			//if !RevisionExists(revisionRef) {
			//	return error.New("Revision/Tag %s does not exists in traffic block.")
			//}

			// provided revisionRef isn't present in traffic block, add it
			traffic = append(traffic, newTarget("", revisionRef, percentInt, false))
		}
	}
	// remove any targets having no tags and 0% traffic portion
	return nil, traffic.RemoveNullTargets()
}
