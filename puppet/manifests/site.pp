# Puppet site manifest — applies to all nodes in all environments.
# The baseline module (puppet/modules/baseline/) handles drift enforcement.
# Hiera data lives in puppet/data/common.yaml.

node default {
  include baseline
}
