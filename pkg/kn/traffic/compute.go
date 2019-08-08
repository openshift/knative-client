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
	parts := strings.SplitN(pair, "=", 2)
	if len(parts) != 2 {
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
			target.Tag = ""
			e[i] = target
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
			target.Tag = tag
			e[i] = target
			return e
		}
	}
	e = append(e, newTarget(tag, revision, 0, false))
	return e
}

func (e ServiceTraffic) TagLatestRevision(tag string) ServiceTraffic {
	for i, target := range e {
		if *target.LatestRevision {
			target.Tag = tag
			e[i] = target
			return e
		}
	}
	e = append(e, newTarget(tag, "", 0, true))
	return e
}

func (e ServiceTraffic) SetTrafficByRevision(revision string, percent int) {
	for i, target := range e {
		if target.RevisionName == revision {
			target.Percent = percent
			e[i] = target
		}
	}
}

func (e ServiceTraffic) SetTrafficByTag(tag string, percent int) {
	for i, target := range e {
		if target.Tag == tag {
			target.Percent = percent
			e[i] = target
			break
		}
	}
}

func (e ServiceTraffic) SetTrafficByLatestRevision(percent int) {
	for i, target := range e {
		if *target.LatestRevision {
			target.Percent = percent
			e[i] = target
			break
		}
	}
}

func (e ServiceTraffic) ResetAllTargetPercent() {
	for i, target := range e {
		target.Percent = 0
		e[i] = target
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

// verifies if user has repeated 'LATEST' field in --tag-revision or --traffic flags
func verifyIfLatestRevisionRefRepeated(trafficFlags *flags.Traffic) error {
	var latestRevisionTag = false
	var latestRevisionTraffic = false

	for _, each := range trafficFlags.RevisionsTags {
		revision, _, err := splitByEqualSign(each)

		if err != nil {
			return err
		}

		if latestRevisionTag && revision == latestRevisionRef {
			return errors.New(fmt.Sprintf("Repetition of identifier %s for flag --tag-revision "+
				"is not allowed. Use only once with --tag flag.", latestRevisionRef))
		}

		if revision == latestRevisionRef {
			latestRevisionTag = true
		}
	}

	for _, each := range trafficFlags.RevisionsPercentages {
		revisionRef, _, err := splitByEqualSign(each)

		if err != nil {
			return err
		}

		if latestRevisionTraffic && revisionRef == latestRevisionRef {
			return errors.New(fmt.Sprintf("Repetition of identifier %s for flag --traffic "+
				"is not allowed. Use this only once with --tag flag.", latestRevisionRef))
		}

		if revisionRef == latestRevisionRef {
			latestRevisionTraffic = true
		}
	}
	return nil
}

func trafficBlockOfService(service *v1alpha1.Service) []v1alpha1.TrafficTarget {
	return service.Spec.Traffic
}

func Compute(cmd *cobra.Command, service *v1alpha1.Service, trafficFlags *flags.Traffic) (error, []v1alpha1.TrafficTarget) {
	// Verify if the input is sane
	if err := verifyIfLatestRevisionRefRepeated(trafficFlags); err != nil {
		return err, nil
	}

	traffic := newServiceTraffic(trafficBlockOfService(service))

	// First precedence: Untag revisions
	for _, tag := range trafficFlags.UntagRevisions {
		traffic.UntagRevision(tag)
	}

	for _, each := range trafficFlags.RevisionsTags {
		revision, tag, err := splitByEqualSign(each)

		if err != nil {
			return err, nil
		}

		// apply requested tag only if it doesnt exist in traffic block
		if traffic.IsTagPresent(tag) {
			return errors.New(fmt.Sprintf("Refusing to overwrite existing tag in service, "+
				"add flag '--untag-revision %s' in command to untag it.\n", tag)), nil
		}

		// Second precedence: Tag latestRevision
		if revision == latestRevisionRef {
			traffic = traffic.TagLatestRevision(tag)
		} else {
			// Third precedence: Tag other revisions
			traffic = traffic.TagRevision(tag, revision)
		}
	}

	if cmd.Flags().Changed("traffic") {
		// reset existing traffic portions as what's on CLI is desired state of traffic split portions
		traffic.ResetAllTargetPercent()

		for _, each := range trafficFlags.RevisionsPercentages {
			// revisionRef works here as either revision or tag as either can be specified on CLI
			revisionRef, percent, err := splitByEqualSign(each)
			if err != nil {
				return err, nil
			}

			percentInt, err := strconv.Atoi(percent)
			if err != nil {
				return err, nil
			}

			// fourth precendence: set traffic for latest revision
			if revisionRef == latestRevisionRef {
				if traffic.IsLatestRevisionTrue() {
					traffic.SetTrafficByLatestRevision(percentInt)
				} else {
					// if no latestRevision ref is present in traffic block
					traffic = append(traffic, newTarget("", "", percentInt, true))
				}
				continue
			}

			// fifth precendence: set traffic for rest of revisions
			// check if given revisionRef is a tag
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
