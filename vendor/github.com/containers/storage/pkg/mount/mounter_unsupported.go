// +build !linux

package mount

func mount(device, target, mType string, flag uintptr, data string) error {
	panic("Not implemented")
}
