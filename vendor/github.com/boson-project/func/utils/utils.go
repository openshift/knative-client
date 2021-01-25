package utils

import (
	"sort"
	"strings"

	"github.com/boson-project/func/buildpacks"
)

//RuntimeList returns the list of supported runtimes
//as comma seperated strings
func RuntimeList() string {
	rb := buildpacks.RuntimeToBuildpack
	runtimes := make([]string, 0, len(rb))
	for k := range rb {
		runtimes = append(runtimes, k)
	}
	sort.Strings(runtimes)
	//make it more grammatical :)
	s := runtimes[:len(runtimes)-1]
	str := strings.Join(s, ", ")
	str = str + " and " + runtimes[len(runtimes)-1]
	return str
}
