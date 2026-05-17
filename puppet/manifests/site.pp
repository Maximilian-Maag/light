# Puppet site manifest — applies to all nodes in all environments.
# This is the pull-based baseline: runs every 30 minutes.
# Anything defined here CANNOT be overridden by manual changes or Ansible.

node default {
  include baseline
}
