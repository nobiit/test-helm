#!/usr/bin/env bash
set -e

name=test

if [ $(multipass list --format json | jq -r '.list[].name' | grep -c "^${name}$") == 0 ]; then
  multipass launch -c 2 -m 4G -d 20G -n ${name} 20.04
fi

multipass exec ${name} -- bash <<-EOF
	set -e
	sudo apt-get -qq update
	sudo apt-get -qq install -y linux-generic-hwe-\$(lsb_release -rs)
	if ! [ -z "\$(/usr/lib/update-notifier/update-motd-reboot-required)" ]; then
	  sudo reboot
	fi
EOF

while ! [ -z $(multipass list --format json | jq -r '.list[] | select(.state != "Running") | 1') ]; do
  sleep 1
done

multipass exec ${name} -- bash <<-EOF
	set -e
	if ! [ -z \$(which kubeadm) ]; then
	  rm -rf $(basename $(pwd))/
	  sudo kubeadm reset -f
	  if [ -d /var/run/cilium/cgroupv2/system.slice/ ]; then
	    sudo umount /var/run/cilium/cgroupv2/
	  fi
	  sudo rm -rf /etc/kubernetes/ /var/lib/kubelet/ /var/run/cilium/ /var/log/containers/ /var/log/pods/
	fi
EOF

multipass transfer -r $(pwd)/ ${name}:

multipass exec ${name} -- bash <<-EOF
	set -e
	curl -fsL s.nobidev.com/install-micro.sh
	curl -fsL s.nobidev.com/setup-k8s.sh | bash -exs -
	curl -fsL s.nobidev.com/setup-k8s-master.sh | bash -exs -
	export OPENEBS_SPARSE_COUNT=1
	export K8S_INSTALL_PROBLEM_DETECTOR=0
	export K8S_INSTALL_PROMETHEUS=0
	export K8S_INSTALL_RANCHER=0
	export K8S_INSTALL_GRAFANA=0
	export K8S_INSTALL_COREDNS=0
	export K8S_INSTALL_STATUS=0
	curl -fsL s.nobidev.com/setup-k8s-apps.sh | bash -exs -
EOF
